-- =====================================================================
-- TEST for proxy_absent_device_fix.sql   (rolls back - NOTHING IS KEPT)
-- Run AFTER proxy_absent_device_fix.sql.
-- The DO block ENDS WITH AN ERROR ON PURPOSE: that undoes everything it
-- did, and the error message is the report (PASS / FAIL per step).
--
-- Replays your CS-304L case on a temporary course ZZ-TEST:
-- student1 scans with phone X -> teacher sets student1 absent ->
-- admin resets phones -> student3 scans with the SAME phone X.
-- Users: teacher ashfaq (course teacher), teacher riaz (other teacher),
-- admin, student1 / student2 / student3.
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

create function pg_temp.row_of(s uuid, c uuid) returns text
language sql as $$
  select coalesce(string_agg(status || '/' || coalesce(device_id, 'no-phone'), ','), 'no row')
  from public.attendance where student_id = s and course_id = c;
$$;

do $$
declare
  s1 uuid; s2 uuid; s3 uuid; t_a uuid; t_b uuid; adm uuid; c uuid;
  pk_now timestamp := now() at time zone 'Asia/Karachi';
  r jsonb; st text; sess uuid; tok text; n int; v text;
  report text := '';
begin
  perform pg_temp.act_as_db();
  select id into s1  from profiles where email = 'student1@test.com';
  select id into s2  from profiles where email = 'student2@test.com';
  select id into s3  from profiles where email = 'student3@test.com';
  select id into t_a from profiles where email = 'ashfaq@test.com';
  select id into t_b from profiles where email = 'riaz@test.com';
  select id into adm from profiles where email = 'admin@test.com';
  if s1 is null or s2 is null or s3 is null or t_a is null or t_b is null or adm is null then
    raise exception 'Test users missing. Nothing was changed.';
  end if;

  -- Setup (undone at the end)
  update profiles set device_id = null where id in (s1, s2, s3);
  insert into courses (name, code, semester, teacher_id)
    values ('Test Course', 'ZZ-TEST', 'TEST', t_a) returning id into c;
  insert into enrollments (student_id, course_id) values (s1, c), (s2, c), (s3, c);
  insert into timetable (course_id, day_of_week, start_time, end_time)
    values (c, extract(isodow from pk_now)::smallint,
            (pk_now - interval '1 minute')::time,
            least((pk_now + interval '30 minutes')::time, time '23:59:00'));

  perform pg_temp.act_as(t_a);
  r := public.start_session(c);
  sess := (r->>'session_id')::uuid; tok := r->>'token';
  report := report || pg_temp.chk('0. teacher starts class', r->>'code' = 'STARTED', r->>'code');

  -- 1. student1 scans with phone X
  perform pg_temp.act_as(s1);
  r := public.mark_attendance(tok, 'ZZ-X');
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('1. student1 phone X -> MARKED', r->>'code' = 'MARKED',
    r->>'code' || ' | ' || pg_temp.row_of(s1, c));

  -- 2. While student1 is PRESENT, student3 on phone X is still blocked
  perform pg_temp.act_as(s3);
  r := public.mark_attendance(tok, 'ZZ-X');
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('2. student3 on X while student1 present -> blocked',
    r->>'code' in ('DEVICE_MULTI_STUDENT', 'DEVICE_ALREADY_BOUND') and pg_temp.row_of(s3, c) = 'no row',
    r->>'code' || ' | ' || pg_temp.row_of(s3, c));

  -- 3. Teacher sets student1 absent; admin resets student1's phone
  perform pg_temp.act_as(t_a);
  r := public.edit_attendance(sess, s1, 'absent', 'test');
  perform pg_temp.act_as(adm);
  r := public.reset_device(s1);
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('3. student1 absent, row keeps phone X as evidence',
    pg_temp.row_of(s1, c) = 'absent/ZZ-X', pg_temp.row_of(s1, c));

  -- 4. YOUR CASE: student3 scans with the same phone X -> now allowed
  perform pg_temp.act_as(s3);
  r := public.mark_attendance(tok, 'ZZ-X');
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('4. student3 on X after student1 absent -> MARKED (not blocked)',
    r->>'code' = 'MARKED' and pg_temp.row_of(s3, c) = 'present/ZZ-X'
    and pg_temp.row_of(s1, c) = 'absent/ZZ-X',
    r->>'code' || ' | s3=' || pg_temp.row_of(s3, c) || ' s1=' || pg_temp.row_of(s1, c));

  -- 5. student2 on phone X while student3 is PRESENT on it -> blocked
  perform pg_temp.act_as(s2);
  r := public.mark_attendance(tok, 'ZZ-X');
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('5. student2 on X while student3 present -> DEVICE_MULTI_STUDENT',
    r->>'code' = 'DEVICE_MULTI_STUDENT' and pg_temp.row_of(s2, c) = 'no row',
    r->>'code' || ' | ' || pg_temp.row_of(s2, c));

  -- 6. The database itself refuses two PRESENT rows with one phone
  begin
    update attendance set status = 'present' where session_id = sess and student_id = s1;
    v := 'allowed';
  exception when unique_violation then
    v := 'unique_violation';
  end;
  report := report || pg_temp.chk('6. index blocks 2 present rows on one phone', v = 'unique_violation', v);

  -- 7. Alerts: course teacher only
  perform pg_temp.act_as(t_a);
  select count(*) into n from audit_logs where session_id = sess and event_type = 'DEVICE_MULTI_STUDENT';
  report := report || pg_temp.chk('7. course teacher sees the proxy alerts', n >= 1, n::text);
  update audit_logs set is_read = true where session_id = sess;
  get diagnostics n = row_count;
  report := report || pg_temp.chk('7. course teacher can mark them read', n >= 1, n || ' rows');

  perform pg_temp.act_as(adm);
  select count(*) into n from audit_logs where session_id = sess;
  report := report || pg_temp.chk('7. ADMIN sees none of them', n = 0, n::text);
  select count(*) into n from audit_logs;
  report := report || pg_temp.chk('7. ADMIN sees no alert at all (whole table)', n = 0, n::text);

  perform pg_temp.act_as(t_b);
  select count(*) into n from audit_logs where session_id = sess;
  report := report || pg_temp.chk('7. other teacher sees none', n = 0, n::text);

  perform pg_temp.act_as(s3);
  select count(*) into n from audit_logs;
  report := report || pg_temp.chk('7. student sees none', n = 0, n::text);

  raise exception E'TEST REPORT (everything was rolled back)\nFAIL count: %\n%',
    (length(report) - length(replace(report, 'FAIL  ', ''))) / length('FAIL  '),
    report;
end $$;
