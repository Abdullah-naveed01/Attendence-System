-- =====================================================================
-- proxy_absent_device_fix_part_c.sql
-- PART C only (Parts A and B of proxy_absent_device_fix.sql are already
-- applied). Paste THIS WHOLE FILE into the SQL Editor and click Run.
--
-- mark_attendance = the deployed version with TWO changes (CHANGED):
--   1. DEVICE_MULTI_STUDENT only counts another student's PRESENT/LATE
--      row with this phone (absent / excused rows are ignored).
--   2. unique_violation: if another student became present with this
--      phone at the same moment, answer DEVICE_MULTI_STUDENT.
-- =====================================================================

create or replace function public.mark_attendance(p_token text, p_device_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_session      public.sessions%rowtype;
  v_my_device    text;
  v_owner        uuid;
  v_status       text;   -- status of my row in this session (null = no row)
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    return jsonb_build_object('ok', false, 'code', 'NO_DEVICE_ID');
  end if;

  select * into v_session from public.sessions
   where qr_token = p_token and is_active and qr_expires_at > now();
  if not found then
    perform public.log_event('INVALID_QR', 'low', null, null, v_uid, null, p_device_id,
                             jsonb_build_object('reason', 'expired or unknown token'));
    return jsonb_build_object('ok', false, 'code', 'INVALID_QR');
  end if;

  select device_id into v_my_device from public.profiles where id = v_uid;
  select id into v_owner from public.profiles where device_id = p_device_id;

  if not public.is_enrolled(v_session.course_id) then
    perform public.log_event('NOT_ENROLLED', 'low', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id);
    return jsonb_build_object('ok', false, 'code', 'NOT_ENROLLED');
  end if;

  -- Only a PRESENT / LATE row means "already marked".
  select status into v_status from public.attendance
   where session_id = v_session.id and student_id = v_uid;
  if v_status in ('present', 'late') then
    perform public.log_event('DUPLICATE_ATTEMPT', 'low', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id);
    return jsonb_build_object('ok', false, 'code', 'ALREADY_MARKED');
  end if;

  -- CHANGED (1): only another student's PRESENT / LATE row with this phone
  if exists (select 1 from public.attendance
              where session_id = v_session.id and device_id = p_device_id and student_id <> v_uid
                and status in ('present', 'late')) then
    perform public.log_event('DEVICE_MULTI_STUDENT', 'high', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id);
    return jsonb_build_object('ok', false, 'code', 'DEVICE_MULTI_STUDENT');
  end if;

  if v_my_device is not null and v_my_device <> p_device_id then
    perform public.log_event('DEVICE_MISMATCH', 'high', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id,
                             jsonb_build_object('registered_device', v_my_device));
    return jsonb_build_object('ok', false, 'code', 'DEVICE_MISMATCH');
  end if;

  if v_my_device is null and v_owner is not null and v_owner <> v_uid then
    perform public.log_event('DEVICE_ALREADY_BOUND', 'high', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id);
    return jsonb_build_object('ok', false, 'code', 'DEVICE_ALREADY_BOUND');
  end if;

  -- Save the scan
  begin
    if v_status is null then
      insert into public.attendance (session_id, student_id, course_id, device_id, method)
      values (v_session.id, v_uid, v_session.course_id, p_device_id, 'qr');
    else
      update public.attendance
         set status = 'present', method = 'qr', device_id = p_device_id, marked_at = now(),
             edited_by = null, edited_at = null, edit_reason = null
       where session_id = v_session.id and student_id = v_uid
         and status not in ('present', 'late');
      if not found then
        perform public.log_event('DUPLICATE_ATTEMPT', 'low', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id);
        return jsonb_build_object('ok', false, 'code', 'ALREADY_MARKED');
      end if;
    end if;
  exception when unique_violation then
    -- CHANGED (2): another student became present with this phone at the same moment
    if exists (select 1 from public.attendance
                where session_id = v_session.id and device_id = p_device_id and student_id <> v_uid
                  and status in ('present', 'late')) then
      perform public.log_event('DEVICE_MULTI_STUDENT', 'high', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id,
                               jsonb_build_object('reason', 'race condition'));
      return jsonb_build_object('ok', false, 'code', 'DEVICE_MULTI_STUDENT');
    end if;
    -- a row for me was created at the same moment: same rule as above
    update public.attendance
       set status = 'present', method = 'qr', device_id = p_device_id, marked_at = now(),
           edited_by = null, edited_at = null, edit_reason = null
     where session_id = v_session.id and student_id = v_uid
       and status not in ('present', 'late');
    if not found then
      perform public.log_event('DUPLICATE_ATTEMPT', 'low', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id,
                               jsonb_build_object('reason', 'race condition'));
      return jsonb_build_object('ok', false, 'code', 'ALREADY_MARKED');
    end if;
  end;

  if v_my_device is null then
    update public.profiles set device_id = p_device_id where id = v_uid;
  end if;

  return jsonb_build_object('ok', true, 'code', 'MARKED');
end;
$$;
