-- =====================================================================
-- FULL PROJECT SERVER TEST  (rolls back - NOTHING IS KEPT)
--
-- Everything runs in one DO block that ENDS WITH AN ERROR ON PURPOSE.
-- In PostgreSQL that error undoes everything the block did: test
-- courses, timetable slot, sessions, attendance, alerts, announcements,
-- role and phone changes all disappear again.
--
-- HOW TO READ THE RESULT: the red "error" message IS the report.
-- Each line starts with PASS or FAIL and the requirement number.
--
-- It "acts as" a logged-in user exactly like the app (role
-- 'authenticated' + that user's id), so RLS and auth.uid() apply.
-- Users: admin@test.com, ashfaq@test.com (teacher A), riaz@test.com
-- (teacher B), student1/2/3@test.com.
-- Test courses: ZZ-TEST (teacher A, timetable slot NOW, student1+2
-- enrolled), ZZ-NOSLOT (teacher A, no slot).
-- Run before 23:30 Pakistan time (the test slot must fit in one day).
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

create function pg_temp.chk(p_fr text, p_what text, p_ok boolean, p_got text)
returns text language sql as $$
  select E'\n' || case when coalesce(p_ok, false) then 'PASS  ' else 'FAIL  ' end
         || rpad(p_fr, 7) || p_what
         || case when coalesce(p_ok, false) then ''
                 else '   (got: ' || coalesce(p_got, 'null') || ')' end;
$$;

-- Runs a query that returns one jsonb value; errors come back as text.
create function pg_temp.call(p_sql text) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  execute p_sql into r;
  return r;
exception when others then
  return jsonb_build_object('code', 'ERROR: ' || sqlerrm);
end $$;

-- Runs a statement; returns 'OK' or the error text.
create function pg_temp.try_sql(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return 'ERROR: ' || sqlerrm;
end $$;

do $$
declare
  s1 uuid; s2 uuid; s3 uuid; t_a uuid; t_b uuid; adm uuid;
  c_test uuid; c_noslot uuid; c_b uuid;
  pk_now timestamp := now() at time zone 'Asia/Karachi';
  r jsonb; v text; n int;
  sess_a uuid; tok text;
  alert_id uuid;
  report text := '';
begin
  perform pg_temp.act_as_db();
  select id into s1  from profiles where email = 'student1@test.com';
  select id into s2  from profiles where email = 'student2@test.com';
  select id into s3  from profiles where email = 'student3@test.com';
  select id into t_a from profiles where email = 'ashfaq@test.com';
  select id into t_b from profiles where email = 'riaz@test.com';
  select id into adm from profiles where email = 'admin@test.com';
  select id into c_b from courses where teacher_id = t_b order by code limit 1;
  if s1 is null or s2 is null or s3 is null or t_a is null or t_b is null
     or adm is null or c_b is null then
    raise exception 'Test users/courses missing. Nothing was changed.';
  end if;

  -- ---------- Setup (all undone at the end) ----------
  update profiles set device_id = null where id in (s1, s2, s3);
  insert into courses (name, code, semester, teacher_id)
    values ('Test Course', 'ZZ-TEST', 'TEST', t_a) returning id into c_test;
  insert into courses (name, code, semester, teacher_id)
    values ('Test No Slot', 'ZZ-NOSLOT', 'TEST', t_a) returning id into c_noslot;
  insert into enrollments (student_id, course_id) values (s1, c_test), (s2, c_test);
  insert into timetable (course_id, day_of_week, start_time, end_time)
    values (c_test, extract(isodow from pk_now)::smallint,
            (pk_now - interval '1 minute')::time,
            least((pk_now + interval '30 minutes')::time, time '23:59:00'));

  -- =============== Timetable lock + sessions ===============
  perform pg_temp.act_as(t_a);
  r := pg_temp.call(format('select public.start_session(%L::uuid)', c_noslot));
  report := report || pg_temp.chk('FR-22', 'teacher outside slot -> NOT_SCHEDULED', r->>'code' = 'NOT_SCHEDULED', r::text);

  perform pg_temp.act_as(t_b);
  r := pg_temp.call(format('select public.start_session(%L::uuid)', c_test));
  report := report || pg_temp.chk('FR-23', 'other teacher cannot start the course', r->>'code' = 'NOT_ALLOWED', r::text);

  perform pg_temp.act_as(t_a);
  r := pg_temp.call(format('select public.start_session(%L::uuid)', c_test));
  sess_a := (r->>'session_id')::uuid; tok := r->>'token';
  report := report || pg_temp.chk('FR-24', 'teacher starts inside slot -> STARTED', r->>'code' = 'STARTED', r::text);

  perform pg_temp.act_as_db();
  v := pg_temp.try_sql(format(
    'insert into public.sessions (course_id, qr_token, qr_expires_at) values (%L, %L, now())', c_test, 'ZZ-DUP'));
  report := report || pg_temp.chk('FR-25', 'database blocks a 2nd active session', v like 'ERROR%', v);

  perform pg_temp.act_as(adm);
  r := pg_temp.call(format('select public.start_session(%L::uuid)', c_noslot));
  report := report || pg_temp.chk('FR-15', 'admin starts a course with no slot', r->>'code' = 'STARTED', r::text);

  -- =============== QR scans ===============
  perform pg_temp.act_as(s1);
  r := pg_temp.call(format('select public.mark_attendance(%L, %L)', tok, 'ZZ-PHONE-1'));
  report := report || pg_temp.chk('FR-34', 'enrolled student, valid QR -> MARKED', r->>'code' = 'MARKED', r::text);

  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-40', 'first scan registers the phone',
    (select device_id from profiles where id = s1) = 'ZZ-PHONE-1', (select device_id from profiles where id = s1));
  report := report || pg_temp.chk('FR-37', 'row saved for the scanned session and its course',
    exists (select 1 from attendance where student_id = s1 and session_id = sess_a and course_id = c_test), 'no row');

  perform pg_temp.act_as(s1);
  r := pg_temp.call(format('select public.mark_attendance(%L, %L)', tok, 'ZZ-PHONE-1'));
  report := report || pg_temp.chk('FR-35', 'second scan -> already marked',
    r->>'code' in ('DUPLICATE_ATTEMPT', 'ALREADY_MARKED'), r::text);

  perform pg_temp.act_as(s2);
  r := pg_temp.call(format('select public.mark_attendance(%L, %L)', tok, 'ZZ-PHONE-1'));
  report := report || pg_temp.chk('FR-42', 'student2 on student1''s phone -> blocked',
    r->>'code' in ('DEVICE_MULTI_STUDENT', 'DEVICE_ALREADY_BOUND', 'DEVICE_MISMATCH', 'DEVICE_BLOCKED'), r::text);

  perform pg_temp.act_as_db();
  select id into alert_id from audit_logs
   where session_id = sess_a and severity = 'high' and account_id = s2 and device_owner_id = s1 limit 1;
  report := report || pg_temp.chk('FR-43', 'blocked attempt logged with account AND phone owner', alert_id is not null, 'no such row');
  report := report || pg_temp.chk('FR-41', 'blocked attempt created no attendance',
    not exists (select 1 from attendance where session_id = sess_a and student_id = s2), 'row exists');

  perform pg_temp.act_as(s3);
  r := pg_temp.call(format('select public.mark_attendance(%L, %L)', tok, 'ZZ-PHONE-3'));
  report := report || pg_temp.chk('FR-34', 'not enrolled -> NOT_ENROLLED', r->>'code' = 'NOT_ENROLLED', r::text);
  r := pg_temp.call(format('select public.mark_attendance(%L, %L)', 'ZZ-NO-SUCH-TOKEN', 'ZZ-PHONE-3'));
  report := report || pg_temp.chk('FR-36', 'unknown QR -> INVALID_QR', r->>'code' = 'INVALID_QR', r::text);

  -- =============== One session per day + day records ===============
  perform pg_temp.act_as(t_a);
  r := pg_temp.call(format('select public.end_session(%L::uuid)', sess_a));
  report := report || pg_temp.chk('FR-24', 'end_session ends the class', (r->>'ok')::boolean, r::text);

  perform pg_temp.act_as_db();
  select count(*) into n from student_daily_attendance
   where student_id = s2 and course_id = c_test and status = 'absent';
  report := report || pg_temp.chk('FR-45', 'class ended: student2 has ONE absent day', n = 1, n::text);

  perform pg_temp.act_as(t_a);
  r := pg_temp.call(format('select public.start_session(%L::uuid)', c_test));
  tok := r->>'token';
  report := report || pg_temp.chk('FR-26', 'restart same day reopens the SAME session',
    (r->>'session_id')::uuid = sess_a and (r->>'resumed')::boolean, r::text);
  perform pg_temp.act_as_db();
  select count(*) into n from sessions
   where course_id = c_test and (started_at at time zone 'Asia/Karachi')::date = pk_now::date;
  report := report || pg_temp.chk('FR-26', 'still only one session today', n = 1, n::text);

  perform pg_temp.act_as(s2);
  r := pg_temp.call(format('select public.mark_attendance(%L, %L)', tok, 'ZZ-PHONE-2'));
  perform pg_temp.act_as_db();
  select count(*) into n from student_daily_attendance where student_id = s2 and course_id = c_test;
  report := report || pg_temp.chk('FR-45', 'later scan turns the SAME day into present',
    r->>'code' = 'MARKED' and n = 1
    and (select status from student_daily_attendance where student_id = s2 and course_id = c_test) = 'present',
    r::text || ' rows=' || n);

  -- =============== Manual + teacher edit ===============
  perform pg_temp.act_as(t_b);
  r := pg_temp.call(format('select public.mark_manual(%L::uuid, %L::uuid)', sess_a, s1));
  report := report || pg_temp.chk('FR-29', 'other teacher cannot mark manually', r->>'code' = 'NOT_ALLOWED', r::text);

  perform pg_temp.act_as_db();
  insert into enrollments (student_id, course_id) values (s3, c_test);

  perform pg_temp.act_as(t_a);
  r := pg_temp.call(format('select public.edit_attendance(%L::uuid, %L::uuid, %L, %L)', sess_a, s3, 'late', 'test'));
  report := report || pg_temp.chk('FR-48', 'teacher sets absent -> late (creates manual row)', r->>'code' = 'CREATED', r::text);
  r := pg_temp.call(format('select public.edit_attendance(%L::uuid, %L::uuid, %L, %L)', sess_a, s3, 'excused', null));
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-48', 'late -> excused UPDATES the same row (none deleted)',
    r->>'code' = 'UPDATED'
    and (select count(*) from attendance where student_id = s3 and course_id = c_test) = 1
    and (select edited_by from attendance where student_id = s3 and course_id = c_test) = t_a,
    r::text);

  perform pg_temp.act_as(t_b);
  r := pg_temp.call(format('select public.edit_attendance(%L::uuid, %L::uuid, %L, %L)', sess_a, s1, 'absent', null));
  report := report || pg_temp.chk('FR-48', 'other teacher cannot edit', r->>'code' = 'NOT_ALLOWED', r::text);

  perform pg_temp.act_as(s1);
  r := pg_temp.call(format('select public.edit_attendance(%L::uuid, %L::uuid, %L, %L)', sess_a, s1, 'present', null));
  report := report || pg_temp.chk('FR-49', 'student cannot edit (function)', r->>'code' = 'NOT_ALLOWED', r::text);
  v := pg_temp.try_sql(format('update public.attendance set status = ''present'' where student_id = %L', s3));
  report := report || pg_temp.chk('FR-49', 'student cannot update attendance directly', v like 'ERROR%', v);
  v := pg_temp.try_sql(format(
    'insert into public.attendance (session_id, student_id, course_id, method) values (%L, %L, %L, ''qr'')', sess_a, s1, c_test));
  report := report || pg_temp.chk('FR-57', 'student cannot insert attendance directly', v like 'ERROR%', v);

  perform pg_temp.act_as(t_a);
  select count(*) into n from public.get_course_class_days(c_test);
  report := report || pg_temp.chk('FR-48', 'teacher sees one class day for the course', n = 1, n::text);
  perform pg_temp.act_as(t_b);
  select count(*) into n from public.get_course_class_days(c_test);
  report := report || pg_temp.chk('FR-48', 'other teacher sees no records', n = 0, n::text);

  -- =============== Student records ===============
  perform pg_temp.act_as(s1);
  select count(*) into n from public.get_my_attendance_summary()
   where course_id = c_test and total_sessions = 1 and attended_sessions = 1;
  report := report || pg_temp.chk('FR-46', 'percentage counts days: 1 of 1', n = 1, n::text);
  select count(*) into n from public.get_my_course_days(c_test) where status = 'present';
  report := report || pg_temp.chk('FR-47', 'student date-wise view shows the day', n = 1, n::text);

  if to_regprocedure('public.get_my_last_attendance()') is null then
    report := report || pg_temp.chk('FR-39', 'get_my_last_attendance exists', false, 'not created');
  else
    r := pg_temp.call('select to_jsonb(x) from public.get_my_last_attendance() x limit 1');
    report := report || pg_temp.chk('FR-39', 'result card: course + teacher', r->>'course_code' = 'ZZ-TEST', r::text);
  end if;

  -- =============== Alerts: course teacher only ===============
  perform pg_temp.act_as(t_a);
  select count(*) into n from audit_logs where course_id = c_test;
  report := report || pg_temp.chk('FR-44', 'course teacher sees the alert', n > 0, n::text);
  v := pg_temp.try_sql(format('update public.audit_logs set is_read = true where id = %L', alert_id));
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-44', 'teacher can mark it read', (select is_read from audit_logs where id = alert_id), v);
  perform pg_temp.act_as(t_b);
  select count(*) into n from audit_logs where course_id = c_test;
  report := report || pg_temp.chk('FR-44', 'other teacher does NOT see it', n = 0, n::text);
  perform pg_temp.act_as(adm);
  select count(*) into n from audit_logs where course_id = c_test;
  report := report || pg_temp.chk('FR-44', 'admin does NOT see it', n = 0, n::text);
  perform pg_temp.act_as(s1);
  v := pg_temp.try_sql(format(
    'insert into public.audit_logs (event_type, severity, account_id, details) values (''FAKE'', ''low'', %L, ''{}'')', s1));
  report := report || pg_temp.chk('FR-58', 'student cannot write audit_logs', v like 'ERROR%', v);

  -- =============== Device reset: admin only ===============
  perform pg_temp.act_as(t_a);
  r := pg_temp.call(format('select public.reset_device(%L::uuid)', s1));
  report := report || pg_temp.chk('FR-17', 'teacher cannot reset a phone', r->>'code' = 'NOT_ALLOWED', r::text);
  perform pg_temp.act_as(adm);
  r := pg_temp.call(format('select public.reset_device(%L::uuid)', s1));
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-17', 'admin resets the phone',
    (r->>'ok')::boolean and (select device_id from profiles where id = s1) is null, r::text);

  -- =============== Role change (server function) ===============
  perform pg_temp.act_as(t_a);
  r := pg_temp.call(format('select public.set_user_role(%L::uuid, %L)', s3, 'teacher'));
  report := report || pg_temp.chk('FR-14', 'teacher cannot change roles', r->>'code' = 'NOT_ALLOWED', r::text);
  perform pg_temp.act_as(adm);
  r := pg_temp.call(format('select public.set_user_role(%L::uuid, %L)', adm, 'student'));
  report := report || pg_temp.chk('FR-14', 'admin cannot remove own admin role', r->>'code' = 'CANNOT_CHANGE_SELF', r::text);

  -- =============== Announcements ===============
  perform pg_temp.act_as(t_a);
  v := pg_temp.try_sql(format(
    'insert into public.announcements (course_id, teacher_id, title, message) values (%L, %L, ''ZZ title'', ''ZZ msg'')', c_test, t_a));
  report := report || pg_temp.chk('FR-52', 'teacher posts for own course', v = 'OK', v);
  v := pg_temp.try_sql(format(
    'insert into public.announcements (course_id, teacher_id, title, message) values (%L, %L, ''ZZ x'', ''ZZ x'')', c_b, t_a));
  report := report || pg_temp.chk('FR-52', 'teacher cannot post for another teacher''s course', v like 'ERROR%', v);
  perform pg_temp.act_as(s1);
  v := pg_temp.try_sql(format(
    'insert into public.announcements (course_id, teacher_id, title, message) values (%L, %L, ''ZZ s'', ''ZZ s'')', c_test, s1));
  report := report || pg_temp.chk('FR-52', 'student cannot post', v like 'ERROR%', v);
  select count(*) into n from public.get_my_announcements() where title = 'ZZ title';
  report := report || pg_temp.chk('FR-53', 'enrolled student sees it', n = 1, n::text);
  perform pg_temp.act_as_db();
  update announcements set expires_at = now() - interval '1 minute' where title = 'ZZ title';
  perform pg_temp.act_as(s1);
  select count(*) into n from public.get_my_announcements() where title = 'ZZ title';
  report := report || pg_temp.chk('FR-54', 'expired announcement is hidden', n = 0, n::text);

  -- =============== Structure ===============
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-11', 'admin_delete_student exists',
    to_regprocedure('public.admin_delete_student(uuid)') is not null, 'not created');
  report := report || pg_temp.chk('FR-54', 'pg_cron cleanup job exists',
    to_regclass('cron.job') is not null, 'pg_cron not installed');
  select count(*) into n from (select 1 from sessions
    where course_id not in (c_test, c_noslot)
    group by course_id, (started_at at time zone 'Asia/Karachi')::date having count(*) > 1) x;
  report := report || pg_temp.chk('FR-50', 'no course has 2+ sessions on one day', n = 0, n::text);
  select count(*) into n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  report := report || pg_temp.chk('NFR', 'RLS enabled on every table', n = 0, n::text);

  raise exception E'TEST REPORT (everything was rolled back)\nFAIL count: %\n%',
    (length(report) - length(replace(report, 'FAIL  ', ''))) / length('FAIL  '),
    report;
end $$;
