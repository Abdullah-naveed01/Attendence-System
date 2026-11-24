-- =====================================================================
-- TEST for attendance_latest_wins.sql   (rolls back - NOTHING IS KEPT)
-- Run AFTER attendance_latest_wins.sql.
-- The DO block ENDS WITH AN ERROR ON PURPOSE: that undoes everything it
-- did, and the error message is the report (PASS / FAIL per step).
--
-- Acts like the app (role 'authenticated' + the user's id, so RLS and
-- auth.uid() apply). Teacher ashfaq@test.com, student1 (main) and
-- student2 (proxy check). A temporary course ZZ-TEST with a timetable
-- slot open right now is created and removed again.
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

-- The student's row(s) in the course: count + status/method/edited.
create function pg_temp.row_of(s uuid, c uuid) returns text
language sql as $$
  select 'rows=' || count(*) || ' ' ||
         coalesce(string_agg(status || '/' || method || '/' ||
                  case when edited_by is null then 'not-edited' else 'edited' end, ','), '-')
  from public.attendance where student_id = s and course_id = c;
$$;

do $$
declare
  s1 uuid; s2 uuid; t_a uuid; c uuid;
  pk_now timestamp := now() at time zone 'Asia/Karachi';
  r jsonb; st text; sess uuid; tok text; n int;
  report text := '';
begin
  perform pg_temp.act_as_db();
  select id into s1  from profiles where email = 'student1@test.com';
  select id into s2  from profiles where email = 'student2@test.com';
  select id into t_a from profiles where email = 'ashfaq@test.com';
  if s1 is null or s2 is null or t_a is null then
    raise exception 'Test users missing. Nothing was changed.';
  end if;

  -- Setup (undone at the end)
  update profiles set device_id = null where id in (s1, s2);
  insert into courses (name, code, semester, teacher_id)
    values ('Test Course', 'ZZ-TEST', 'TEST', t_a) returning id into c;
  insert into enrollments (student_id, course_id) values (s1, c), (s2, c);
  insert into timetable (course_id, day_of_week, start_time, end_time)
    values (c, extract(isodow from pk_now)::smallint,
            (pk_now - interval '1 minute')::time,
            least((pk_now + interval '30 minutes')::time, time '23:59:00'));

  perform pg_temp.act_as(t_a);
  r := public.start_session(c);
  sess := (r->>'session_id')::uuid; tok := r->>'token';
  report := report || pg_temp.chk('0. teacher starts class', r->>'code' = 'STARTED', r->>'code');

  -- 1. Student scans -> present
  perform pg_temp.act_as(s1);
  r := public.mark_attendance(tok, 'ZZ-PHONE-1');
  perform pg_temp.act_as_db(); st := pg_temp.row_of(s1, c);
  report := report || pg_temp.chk('1. scan -> MARKED, present',
    r->>'code' = 'MARKED' and st = 'rows=1 present/qr/not-edited', r->>'code' || ' | ' || st);

  -- 2. Teacher sets Absent (Attendance Records)
  perform pg_temp.act_as(t_a);
  r := public.edit_attendance(sess, s1, 'absent', 'test');
  perform pg_temp.act_as_db(); st := pg_temp.row_of(s1, c);
  select count(*) into n from attendance where course_id = c and status in ('present', 'late');
  report := report || pg_temp.chk('2. teacher absent -> same row absent, present count 0',
    r->>'code' = 'UPDATED' and st = 'rows=1 absent/qr/edited' and n = 0,
    r->>'code' || ' | ' || st || ' | present=' || n);

  -- 3. Student scans again -> MARKED, SAME row back to present
  perform pg_temp.act_as(s1);
  r := public.mark_attendance(tok, 'ZZ-PHONE-1');
  perform pg_temp.act_as_db(); st := pg_temp.row_of(s1, c);
  select count(*) into n from attendance where course_id = c and status in ('present', 'late');
  report := report || pg_temp.chk('3. scan after absent -> MARKED, same row present, present count 1',
    r->>'code' = 'MARKED' and st = 'rows=1 present/qr/not-edited' and n = 1,
    r->>'code' || ' | ' || st || ' | present=' || n);
  select status into st from student_daily_attendance where student_id = s1 and course_id = c;
  report := report || pg_temp.chk('3. daily view (percentages / records) shows present', st = 'present', st);

  -- 4. Scan once more -> ALREADY_MARKED, nothing changes
  perform pg_temp.act_as(s1);
  r := public.mark_attendance(tok, 'ZZ-PHONE-1');
  perform pg_temp.act_as_db(); st := pg_temp.row_of(s1, c);
  report := report || pg_temp.chk('4. scan again -> ALREADY_MARKED, no change',
    r->>'code' = 'ALREADY_MARKED' and st = 'rows=1 present/qr/not-edited', r->>'code' || ' | ' || st);

  -- 5. Proxy checks still win: student2 (absent) on student1's phone
  perform pg_temp.act_as(t_a);
  r := public.edit_attendance(sess, s2, 'late', null);           -- create a row ...
  r := public.edit_attendance(sess, s2, 'absent', null);         -- ... and set it absent
  perform pg_temp.act_as(s2);
  r := public.mark_attendance(tok, 'ZZ-PHONE-1');
  perform pg_temp.act_as_db(); st := pg_temp.row_of(s2, c);
  report := report || pg_temp.chk('5. student2 (absent) on student1''s phone -> blocked, stays absent',
    r->>'code' in ('DEVICE_MULTI_STUDENT', 'DEVICE_ALREADY_BOUND', 'DEVICE_MISMATCH')
    and st = 'rows=1 absent/manual/edited', r->>'code' || ' | ' || st);
  report := report || pg_temp.chk('5. high alert logged with both ids',
    exists (select 1 from audit_logs where session_id = sess and severity = 'high'
            and account_id = s2 and device_owner_id = s1), '');

  -- 6. student2 with own phone -> present
  perform pg_temp.act_as(s2);
  r := public.mark_attendance(tok, 'ZZ-PHONE-2');
  perform pg_temp.act_as_db(); st := pg_temp.row_of(s2, c);
  report := report || pg_temp.chk('6. student2 own phone -> MARKED, present',
    r->>'code' = 'MARKED' and st = 'rows=1 present/qr/not-edited', r->>'code' || ' | ' || st);

  raise exception E'TEST REPORT (everything was rolled back)\nFAIL count: %\n%',
    (length(report) - length(replace(report, 'FAIL  ', ''))) / length('FAIL  '),
    report;
end $$;
