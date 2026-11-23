-- =====================================================================
-- FR-16 + FR-19: time-locked start_session
--
-- Replaces the EXISTING start_session function (no rename, no wrapper,
-- no start_session_core). Run this whole file once in the SQL Editor.
--
-- What start_session does, in order:
--   1. Not logged in                     -> {ok:false, code:'NOT_AUTHENTICATED'}
--   2. Not admin and not this course's teacher -> {ok:false, code:'NOT_ALLOWED'}
--   3. Not admin and Pakistan time is not inside a timetable slot
--      for this course today            -> {ok:false, code:'NOT_SCHEDULED'}
--   4. The course already has an active session -> reuse it (new QR token)
--      Otherwise                         -> create a new session
--   Answer: {ok:true, code:'STARTED', session_id, token, expires_at}
--
-- Steps 1, 2 and 4 are exactly what the old start_session did.
-- Step 3 is new. Step 4 also handles the rare case where two calls
-- arrive at the same moment (see the comment inside).
-- =====================================================================

create or replace function public.start_session(p_course_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
  v_token      text        := replace(gen_random_uuid()::text, '-', '');
  v_expires    timestamptz := now() + interval '30 seconds';
  -- Current Pakistan time without a time zone, e.g. 2026-11-23 09:15:00
  v_pk_now     timestamp   := now() at time zone 'Asia/Karachi';
begin
  -- 1. Must be logged in
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  end if;

  -- 2. Only an admin or the teacher of this course
  if not (public.my_role() = 'admin' or public.teaches_course(p_course_id)) then
    return jsonb_build_object('ok', false, 'code', 'NOT_ALLOWED');
  end if;

  -- 3. Time lock. Admin can always start. A teacher needs a timetable
  --    slot for this course today: start_time <= now < end_time.
  --    isodow: 1 = Monday ... 7 = Sunday (same as timetable.day_of_week).
  if public.my_role() <> 'admin'
     and not exists (select 1 from public.timetable t
                     where t.course_id   = p_course_id
                       and t.day_of_week = extract(isodow from v_pk_now)
                       and v_pk_now::time >= t.start_time
                       and v_pk_now::time <  t.end_time)
  then
    return jsonb_build_object('ok', false, 'code', 'NOT_SCHEDULED');
  end if;

  -- 4. Reuse the active session if there is one (FR-19)
  select id into v_session_id
  from public.sessions
  where course_id = p_course_id and is_active;

  if v_session_id is null then
    begin
      insert into public.sessions (course_id, qr_token, qr_expires_at)
      values (p_course_id, v_token, v_expires)
      returning id into v_session_id;
    exception when unique_violation then
      -- Two "Start Class" taps at the same moment: the unique index
      -- one_active_session_per_course blocked the second insert.
      -- Use the session the other call just created.
      select id into v_session_id
      from public.sessions
      where course_id = p_course_id and is_active;
      update public.sessions
         set qr_token = v_token, qr_expires_at = v_expires
       where id = v_session_id;
    end;
  else
    update public.sessions
       set qr_token = v_token, qr_expires_at = v_expires
     where id = v_session_id;
  end if;

  return jsonb_build_object('ok', true, 'code', 'STARTED',
    'session_id', v_session_id, 'token', v_token, 'expires_at', v_expires);
end;
$$;

-- Only logged-in users may call it (the function checks the role itself).
revoke execute on function public.start_session(uuid) from public, anon;
grant  execute on function public.start_session(uuid) to authenticated;

-- Make the API see the change immediately.
notify pgrst, 'reload schema';


-- =====================================================================
-- CHECK (read-only): the function now contains the time lock.
-- Expected: has_time_lock = true
-- =====================================================================
select pg_get_functiondef('public.start_session(uuid)'::regprocedure)
         like '%NOT_SCHEDULED%' as has_time_lock;
