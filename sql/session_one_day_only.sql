-- =====================================================================
-- session_one_day_only.sql   (one transaction - all or nothing)
-- RULE: a class session never continues into another day
-- (Asia/Karachi date).
--
-- PART A  New helper end_old_sessions(): ends active sessions.
--         Internal only (the app cannot call it).
-- PART B  start_session: first ends this course's active session from an
--         EARLIER day, then works exactly as before (same-day resume
--         unchanged).
-- PART C  mark_attendance: rejects a QR of a session that started on an
--         earlier day. Also includes the not-yet-applied proxy fix
--         (absent rows no longer block a phone).
-- PART D  pg_cron: every day at 23:59 Pakistan time, end all sessions
--         that are still active.
--
-- Nothing else is changed. No attendance data is changed or deleted.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- PART A. end_old_sessions(course, include_today)
--   course        = null -> all courses
--   include_today = false -> only sessions that started on an EARLIER
--                            day (used by start_session)
--                   true  -> every active session (used by the 23:59 job)
-- ended_at = the end of the timetable slot the session started in;
-- if there is no slot (e.g. the admin started it), the last second of
-- that day. Never later than now. Returns how many sessions it ended.
-- ---------------------------------------------------------------------
create or replace function public.end_old_sessions(
  p_course_id     uuid    default null,
  p_include_today boolean default false
) returns integer
language plpgsql
set search_path = public
as $$
declare
  v_count integer;
begin
  update sessions s
     set is_active = false,
         ended_at  = least(
           now(),
           coalesce(
             -- end of the slot this session started in
             (select ((s.started_at at time zone 'Asia/Karachi')::date + t.end_time)
                       at time zone 'Asia/Karachi'
                from timetable t
               where t.course_id   = s.course_id
                 and t.day_of_week = extract(isodow from s.started_at at time zone 'Asia/Karachi')
                 and (s.started_at at time zone 'Asia/Karachi')::time >= t.start_time
                 and (s.started_at at time zone 'Asia/Karachi')::time <  t.end_time
               order by t.end_time desc
               limit 1),
             -- no slot: last second of the day it started (Pakistan time)
             (((s.started_at at time zone 'Asia/Karachi')::date + 1)::timestamp
                at time zone 'Asia/Karachi') - interval '1 second'))
   where s.is_active
     and (p_course_id is null or s.course_id = p_course_id)
     and (p_include_today
          or (s.started_at at time zone 'Asia/Karachi')::date
             < (now() at time zone 'Asia/Karachi')::date);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Internal only: the app (anon / authenticated) cannot call it.
revoke execute on function public.end_old_sessions(uuid, boolean)
  from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- PART B. start_session = the deployed version + ONE line (NEW).
-- ---------------------------------------------------------------------
create or replace function public.start_session(p_course_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
  v_resumed    boolean     := false;
  v_token      text        := replace(gen_random_uuid()::text, '-', '');
  v_expires    timestamptz := now() + interval '30 seconds';
  v_pk_now     timestamp   := now() at time zone 'Asia/Karachi';
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  end if;

  if not (public.my_role() = 'admin' or public.teaches_course(p_course_id)) then
    return jsonb_build_object('ok', false, 'code', 'NOT_ALLOWED');
  end if;

  if public.my_role() <> 'admin'
     and not exists (select 1 from public.timetable t
                     where t.course_id   = p_course_id
                       and t.day_of_week = extract(isodow from v_pk_now)
                       and v_pk_now::time >= t.start_time
                       and v_pk_now::time <  t.end_time)
  then
    return jsonb_build_object('ok', false, 'code', 'NOT_SCHEDULED');
  end if;

  -- NEW: a session from an earlier day is ended, never continued.
  perform public.end_old_sessions(p_course_id);

  select id into v_session_id
  from public.sessions
  where course_id = p_course_id and is_active;

  if v_session_id is not null then
    update public.sessions
       set qr_token = v_token, qr_expires_at = v_expires
     where id = v_session_id;
  else
    select id into v_session_id
    from public.sessions
    where course_id = p_course_id
      and (started_at at time zone 'Asia/Karachi')::date = v_pk_now::date
    order by started_at desc
    limit 1;

    if v_session_id is not null then
      begin
        update public.sessions
           set is_active          = true,
               ended_at           = null,
               qr_token           = v_token,
               qr_expires_at      = v_expires,
               qr_prev_token      = null,
               qr_prev_expires_at = null
         where id = v_session_id;
        v_resumed := true;
      exception when unique_violation then
        select id into v_session_id
        from public.sessions
        where course_id = p_course_id and is_active;
      end;
    else
      begin
        insert into public.sessions (course_id, qr_token, qr_expires_at)
        values (p_course_id, v_token, v_expires)
        returning id into v_session_id;
      exception when unique_violation then
        select id into v_session_id
        from public.sessions
        where course_id = p_course_id and is_active;
        update public.sessions
           set qr_token = v_token, qr_expires_at = v_expires
         where id = v_session_id;
      end;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'code', 'STARTED',
    'session_id', v_session_id, 'token', v_token, 'expires_at', v_expires,
    'resumed', v_resumed);
end;
$$;


-- ---------------------------------------------------------------------
-- PART C. mark_attendance = the deployed version with THREE changes:
--   NEW (day)   the QR is valid only if its session started TODAY
--               (Pakistan date); otherwise INVALID_QR, as for an
--               expired QR.
--   CHANGED (1) proxy check counts only another student's PRESENT /
--               LATE row with this phone (absent rows do not block).
--   CHANGED (2) two students on one phone at the same moment ->
--               DEVICE_MULTI_STUDENT instead of a database error.
-- ---------------------------------------------------------------------
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
   where qr_token = p_token and is_active and qr_expires_at > now()
     -- NEW (day): only a session that started today (Pakistan date)
     and (started_at at time zone 'Asia/Karachi')::date
         = (now() at time zone 'Asia/Karachi')::date;
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


-- ---------------------------------------------------------------------
-- PART D. Daily job at 23:59 Pakistan time.
-- pg_cron uses UTC: 23:59 Pakistan (UTC+5) = 18:59 UTC -> '59 18 * * *'.
-- Scheduling with the same job name again replaces the old schedule.
-- ---------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'end-active-sessions-daily',
  '59 18 * * *',
  $job$ select public.end_old_sessions(null, true); $job$
);

commit;

-- =====================================================================
-- CHECK (read-only) after running:
-- select jobname, schedule, command from cron.job;
-- select proname from pg_proc where proname = 'end_old_sessions';
-- =====================================================================
