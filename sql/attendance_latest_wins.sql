-- =====================================================================
-- attendance_latest_wins.sql
-- mark_attendance: the LATEST action wins.
-- A student whose row in this session is 'absent' (e.g. set by the
-- teacher) can scan a valid QR and become 'present' again.
--
-- Based on the DEPLOYED mark_attendance (md5 326c2c3b...). Everything is
-- unchanged (login, device id, QR valid + session active, enrolled,
-- device binding, proxy checks + alerts) EXCEPT the parts marked CHANGED:
--   * row 'present' / 'late'      -> ALREADY_MARKED (low alert, as before)
--   * row 'absent' (or 'excused') -> UPDATE the SAME row to 'present',
--                                    method 'qr', this device_id,
--                                    marked_at = now(), teacher edit
--                                    fields cleared            -> MARKED
--   * no row                      -> insert as before          -> MARKED
--   * unique_violation (two scans at the same moment): same rule.
-- A second row is never created; rows are never deleted.
-- No table, view or data is changed. Grants stay as they are.
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
  v_status       text;   -- CHANGED: status of my row in this session (null = no row)
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

  -- CHANGED: only a PRESENT / LATE row means "already marked".
  -- An absent / excused row does not stop the scan (it is updated below,
  -- after the device checks).
  select status into v_status from public.attendance
   where session_id = v_session.id and student_id = v_uid;
  if v_status in ('present', 'late') then
    perform public.log_event('DUPLICATE_ATTEMPT', 'low', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id);
    return jsonb_build_object('ok', false, 'code', 'ALREADY_MARKED');
  end if;

  if exists (select 1 from public.attendance
              where session_id = v_session.id and device_id = p_device_id and student_id <> v_uid) then
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

  -- CHANGED: save the scan (insert a new row, or turn MY absent row into present)
  begin
    if v_status is null then
      -- No row yet: insert exactly as before (status defaults to 'present')
      insert into public.attendance (session_id, student_id, course_id, device_id, method)
      values (v_session.id, v_uid, v_session.course_id, p_device_id, 'qr');
    else
      -- My row is absent / excused: the scan is the latest action
      update public.attendance
         set status      = 'present',
             method      = 'qr',
             device_id   = p_device_id,
             marked_at   = now(),
             edited_by   = null,
             edited_at   = null,
             edit_reason = null
       where session_id = v_session.id
         and student_id = v_uid
         and status not in ('present', 'late');
      if not found then
        -- It became present a moment ago (e.g. the teacher marked it)
        perform public.log_event('DUPLICATE_ATTEMPT', 'low', v_session.id, v_session.course_id, v_uid, v_owner, p_device_id);
        return jsonb_build_object('ok', false, 'code', 'ALREADY_MARKED');
      end if;
    end if;
  exception when unique_violation then
    -- A row for me was created at the same moment: apply the same rule.
    update public.attendance
       set status      = 'present',
           method      = 'qr',
           device_id   = p_device_id,
           marked_at   = now(),
           edited_by   = null,
           edited_at   = null,
           edit_reason = null
     where session_id = v_session.id
       and student_id = v_uid
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

-- CHECK (read-only), must show handles_absent = true:
-- select oid::regprocedure, position('absent' in prosrc) > 0 as handles_absent
-- from pg_proc where proname = 'mark_attendance';
