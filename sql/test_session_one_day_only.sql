-- =====================================================================
-- TEST for session_one_day_only.sql   (rolls back - NOTHING IS KEPT)
-- Run AFTER session_one_day_only.sql.
-- The DO block ENDS WITH AN ERROR ON PURPOSE: that undoes everything it
-- did, and the error message is the report (PASS / FAIL per step).
-- Temporary courses ZZ-TEST / ZZ-TEST2, teacher ashfaq, student1/2.
-- Run before 23:30 Pakistan time.
-- =====================================================================

create function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('role', session_user::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create function pg_temp.act_as_db() returns void
language plpgsql as $$
begin
  perform set_config('role', session_user::text, true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.chk(p_step text, p_ok boolean, p_got text)
returns text language sql as $$
  select E'\n' || case when coalesce(p_ok, false) then 'PASS  ' else 'FAIL  ' end
         || p_step || '   [' || coalesce(p_got, 'null') || ']';
$$;

do $$
declare
  s1 uuid; s2 uuid; t_a uuid; c uuid; c2 uuid;
  pk_now  timestamp := now() at time zone 'Asia/Karachi';
  pk_today date     := (now() at time zone 'Asia/Karachi')::date;
  slot_start time   := ((now() at time zone 'Asia/Karachi') - interval '1 minute')::time;
  slot_end   time   := least(((now() at time zone 'Asia/Karachi') + interval '30 minutes')::time, time '23:59:00');
  r jsonb; v text; n int; old_sess uuid; old2 uuid; new_sess uuid; sess2 uuid; ended timestamptz;
  report text := '';
begin
  perform pg_temp.act_as_db();
  select id into s1  from profiles where email = 'student1@test.com';
  select id into s2  from profiles where email = 'student2@test.com';
  select id into t_a from profiles where email = 'ashfaq@test.com';
  if s1 is null or s2 is null or t_a is null then
    raise exception 'Test users missing. Nothing was changed.';
  end if;

  -- Setup: course with a slot today AND the same slot yesterday
  update profiles set device_id = null where id in (s1, s2);
  insert into courses (name, code, semester, teacher_id)
    values ('Test Course', 'ZZ-TEST', 'TEST', t_a) returning id into c;
  insert into courses (name, code, semester, teacher_id)
    values ('Test Course 2', 'ZZ-TEST2', 'TEST', t_a) returning id into c2;
  insert into enrollments (student_id, course_id) values (s1, c), (s2, c), (s1, c2);
  insert into timetable (course_id, day_of_week, start_time, end_time) values
    (c, extract(isodow from pk_now)::smallint, slot_start, slot_end),
    (c, extract(isodow from pk_now - interval '1 day')::smallint, slot_start, slot_end);

  -- Yesterday's class, NEVER ended, with student1 present in it
  insert into sessions (course_id, started_at, is_active, qr_token, qr_expires_at)
    values (c, now() - interval '1 day', true, 'ZZ-OLD-1', now() - interval '1 day')
    returning id into old_sess;
  insert into attendance (session_id, student_id, course_id, device_id, method, marked_at)
    values (old_sess, s1, c, 'ZZ-P1', 'qr', now() - interval '1 day');

  -- 1. Teacher starts today -> yesterday's session is ended, NEW one created
  perform pg_temp.act_as(t_a);
  r := public.start_session(c);
  new_sess := (r->>'session_id')::uuid;
  perform pg_temp.act_as_db();
  select ended_at into ended from sessions where id = old_sess;
  report := report || pg_temp.chk('1. start today -> NEW session (not yesterday''s)',
    r->>'code' = 'STARTED' and new_sess <> old_sess and not (r->>'resumed')::boolean,
    r::text);
  report := report || pg_temp.chk('1. yesterday''s session ended at its slot end (yesterday)',
    (select not is_active from sessions where id = old_sess)
    and ended = ((pk_today - 1) + slot_end) at time zone 'Asia/Karachi',
    'ended_at PK = ' || (ended at time zone 'Asia/Karachi')::text);
  select count(*) into n from attendance where session_id = new_sess;
  report := report || pg_temp.chk('1. new session starts with EMPTY attendance', n = 0, n::text);
  select count(*) into n from attendance where session_id = old_sess;
  report := report || pg_temp.chk('1. yesterday''s attendance kept', n = 1, n::text);

  -- 2. Same day: end + start again -> SAME session (resume unchanged)
  perform pg_temp.act_as(t_a);
  r := public.end_session(new_sess);
  r := public.start_session(c);
  report := report || pg_temp.chk('2. end + start again today -> SAME session, resumed',
    (r->>'session_id')::uuid = new_sess and (r->>'resumed')::boolean, r::text);
  perform pg_temp.act_as_db();
  select count(*) into n from sessions where course_id = c;
  report := report || pg_temp.chk('2. course has exactly 2 sessions (yesterday + today)', n = 2, n::text);

  -- 3. Today's QR works
  perform pg_temp.act_as(s2);
  r := public.mark_attendance(r->>'token', 'ZZ-P2');
  report := report || pg_temp.chk('3. today''s QR -> MARKED', r->>'code' = 'MARKED', r->>'code');

  -- 4. QR of a session from YESTERDAY that is still active -> rejected
  perform pg_temp.act_as_db();
  insert into sessions (course_id, started_at, is_active, qr_token, qr_expires_at)
    values (c2, now() - interval '1 day', true, 'ZZ-OLD-2', now() + interval '30 seconds')
    returning id into old2;
  perform pg_temp.act_as(s1);
  r := public.mark_attendance('ZZ-OLD-2', 'ZZ-P1');
  perform pg_temp.act_as_db();
  select count(*) into n from attendance where session_id = old2;
  report := report || pg_temp.chk('4. QR of yesterday''s session -> INVALID_QR, nothing saved',
    r->>'code' = 'INVALID_QR' and n = 0, r->>'code' || ' rows=' || n);

  -- 5. The 23:59 job's call ends every active session (here: ZZ courses)
  n := public.end_old_sessions(c, true) + public.end_old_sessions(c2, true);
  report := report || pg_temp.chk('5. end_old_sessions(..., true) ends the active sessions',
    n = 2 and not exists (select 1 from sessions where course_id in (c, c2) and is_active),
    n || ' ended');
  report := report || pg_temp.chk('5. today''s session ended no later than now',
    (select ended_at <= now() from sessions where id = new_sess), '');

  -- 6. Daily job exists: 23:59 Pakistan = 18:59 UTC
  select count(*) into n from cron.job
   where jobname = 'end-active-sessions-daily' and schedule = '59 18 * * *';
  report := report || pg_temp.chk('6. pg_cron job at 59 18 * * * (UTC)', n = 1, n::text);

  -- 7. The app cannot call the helper
  perform pg_temp.act_as(s1);
  begin
    perform public.end_old_sessions();
    v := 'allowed';
  exception when insufficient_privilege then
    v := 'permission denied';
  end;
  report := report || pg_temp.chk('7. app cannot call end_old_sessions', v = 'permission denied', v);

  -- 8. History / percentage: each day is a separate class
  perform pg_temp.act_as(s1);
  select count(*) into n from public.get_my_course_days(c);
  report := report || pg_temp.chk('8. student1 history shows 2 separate days', n = 2, n::text);
  select attended_sessions || '/' || total_sessions into v
    from public.get_my_attendance_summary() where course_id = c;
  report := report || pg_temp.chk('8. student1 percentage: present yesterday, absent today = 1/2',
    v = '1/2', v);

  raise exception E'TEST REPORT (everything was rolled back)\nFAIL count: %\n%',
    (length(report) - length(replace(report, 'FAIL  ', ''))) / length('FAIL  '),
    report;
end $$;
