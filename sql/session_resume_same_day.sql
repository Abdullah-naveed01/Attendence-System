-- =====================================================================
-- ONE SESSION PER COURSE PER DAY (Pakistan time, Asia/Karachi)
--
-- Problem: End Class + Start Class on the same day created a NEW, empty
-- session. The live list restarted at 0 and an already-marked student
-- could be marked again (duplicates are blocked only per session).
--
-- New start_session, in order:
--   1. not logged in                       -> NOT_AUTHENTICATED
--   2. not admin and not this course's teacher -> NOT_ALLOWED
--   3. not admin and outside a timetable slot -> NOT_SCHEDULED
--   4. a session of this course is ACTIVE  -> reuse it (new QR token)
--   5. NEW: this course already had a session TODAY that was ended
--      -> REOPEN it: is_active = true, ended_at = null, new QR token.
--      started_at is NOT changed, so the first start time of the day
--      is kept.
--   6. otherwise                           -> create a new session
--   Answer: {ok:true, code:'STARTED', session_id, token, expires_at,
--            resumed}   ("resumed" = true when step 5 happened)
--
-- Steps 1-4 and 6 are exactly as before. Only step 5 is new.
-- "Today" = the Asia/Karachi date of started_at.
-- The unique index one_active_session_per_course still allows only one
-- active session per course.
-- =====================================================================

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
  -- Current Pakistan time without a time zone, e.g. 2026-11-24 11:54:00
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
  if public.my_role() <> 'admin'
     and not exists (select 1 from public.timetable t
                     where t.course_id   = p_course_id
                       and t.day_of_week = extract(isodow from v_pk_now)
                       and v_pk_now::time >= t.start_time
                       and v_pk_now::time <  t.end_time)
  then
    return jsonb_build_object('ok', false, 'code', 'NOT_SCHEDULED');
  end if;

  -- 4. Reuse the active session if there is one
  select id into v_session_id
  from public.sessions
  where course_id = p_course_id and is_active;

  if v_session_id is not null then
    update public.sessions
       set qr_token = v_token, qr_expires_at = v_expires
     where id = v_session_id;

  else
    -- 5. NEW: reopen today's session of this course (if any)
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
        -- Another "Start Class" tap activated a session at the same
        -- moment: use that one.
        select id into v_session_id
        from public.sessions
        where course_id = p_course_id and is_active;
      end;

    else
      -- 6. No session today: create a new one (as before)
      begin
        insert into public.sessions (course_id, qr_token, qr_expires_at)
        values (p_course_id, v_token, v_expires)
        returning id into v_session_id;
      exception when unique_violation then
        -- Two "Start Class" taps at the same moment: the unique index
        -- one_active_session_per_course blocked the second insert.
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

-- Same rights as before
revoke execute on function public.start_session(uuid) from public, anon;
grant  execute on function public.start_session(uuid) to authenticated;

notify pgrst, 'reload schema';

-- CHECK (read-only): the new step is in the function. Expected: true
select pg_get_functiondef('public.start_session(uuid)'::regprocedure)
         like '%v_resumed := true%' as has_same_day_resume;
