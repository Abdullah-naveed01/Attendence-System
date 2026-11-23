-- =====================================================================
-- FULL SERVER TEST (FR-7, 12, 16-18, 21-24, 26, 28, 33-36, 38-46, 48)
--
-- SAFE: NOTHING IS KEPT. Everything runs in one DO block that ENDS WITH
-- AN ERROR ON PURPOSE. In PostgreSQL an error undoes everything the
-- block did: test courses, timetable slot, sessions, attendance,
-- audit_logs rows and phone bindings all disappear again.
--
-- HOW TO READ THE RESULT: the red "error" message at the end IS the
-- report. Every line starts with PASS or FAIL and the FR number.
--
-- How it works:
--   - "act as" a user by setting the same login values Supabase sets
--     for a real app request (role 'authenticated' + the user's id), so
--     RLS policies and auth.uid() behave exactly like in the app
--   - calls the REAL server functions: start_session, refresh_qr_token,
--     end_session, mark_attendance, mark_manual, reset_device, ...
--   - test courses ZZ-TEST (with a timetable slot right now) and
--     ZZ-NOSLOT (no slot), both taught by ashfaq@test.com;
--     student1 + student2 enrolled in ZZ-TEST, student3 NOT enrolled
--   - fake phone IDs TEST-PHONE-1 / TEST-PHONE-2 / TEST-PHONE-3
--
-- Run the WHOLE file in the Supabase SQL Editor.
-- (Run it before 23:30 Pakistan time; the test slot must fit in one day.)
-- =====================================================================

-- ---------- Helpers (temporary, removed with the rollback) ----------

-- Act as a logged-in app user (RLS + auth.uid() apply)
create function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('role', session_user::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

-- Back to the SQL Editor's own database user (for setup and checks)
create function pg_temp.act_as_db() returns void
language plpgsql as $$
begin
  perform set_config('role', session_user::text, true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- One report line
create function pg_temp.chk(p_fr text, p_what text, p_ok boolean, p_got text)
returns text language sql as $$
  select E'\n' || case when coalesce(p_ok, false) then 'PASS  ' else 'FAIL  ' end
         || rpad(p_fr, 7) || p_what
         || case when coalesce(p_ok, false) then ''
                 else '   (got: ' || coalesce(p_got, 'null') || ')' end;
$$;

-- Server calls that never stop the test (errors are returned as text)
create function pg_temp.scan(p_token text, p_device text) returns text
language plpgsql as $$
begin
  return public.mark_attendance(p_token, p_device) ->> 'code';
exception when others then return 'ERROR: ' || sqlerrm;
end $$;

create function pg_temp.start(p_course uuid) returns jsonb
language plpgsql as $$
begin
  return to_jsonb(public.start_session(p_course));
exception when others then return jsonb_build_object('code', 'ERROR: ' || sqlerrm);
end $$;

create function pg_temp.call_jsonb(p_sql text) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  execute p_sql into r;
  return r;
exception when others then return jsonb_build_object('code', 'ERROR: ' || sqlerrm);
end $$;

create function pg_temp.try_sql(p_sql text) returns text
language plpgsql as $$
begin
  execute p_sql;
  return 'OK';
exception when others then return 'ERROR: ' || sqlerrm;
end $$;

-- ---------- The test ----------
do $$
declare
  s1 uuid; s2 uuid; s3 uuid; t_a uuid; t_b uuid; adm uuid;
  c_test uuid; c_noslot uuid;
  pk_now timestamp := now() at time zone 'Asia/Karachi';
  r jsonb; v text; n int;
  sess_a uuid; tok_a text; tok_new text; sess_b uuid; tok_b text; sess_adm uuid;
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
  if s1 is null or s2 is null or s3 is null or t_a is null or t_b is null or adm is null then
    raise exception 'Test users missing (student1-3, ashfaq, riaz, admin). Nothing was changed.';
  end if;

  -- ---------- Setup (undone at the end) ----------
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

  -- ================= Sessions and time lock =================
  perform pg_temp.act_as(t_a);
  r := pg_temp.start(c_noslot);
  report := report || pg_temp.chk('FR-21', 'teacher, course without a slot now -> NOT_SCHEDULED', r->>'code' = 'NOT_SCHEDULED', r->>'code');

  perform pg_temp.act_as(t_b);
  r := pg_temp.start(c_test);
  report := report || pg_temp.chk('FR-22', 'other teacher cannot start this course -> NOT_ALLOWED', r->>'code' = 'NOT_ALLOWED', r->>'code');

  perform pg_temp.act_as(t_a);
  r := pg_temp.start(c_test);
  sess_a := (r->>'session_id')::uuid; tok_a := r->>'token';
  report := report || pg_temp.chk('FR-23', 'teacher starts class inside the slot -> STARTED', r->>'code' = 'STARTED', r->>'code');

  r := pg_temp.start(c_test);
  report := report || pg_temp.chk('FR-24', 'second Start reuses the same session', (r->>'session_id')::uuid = sess_a, r->>'session_id');
  tok_a := coalesce(r->>'token', tok_a);

  perform pg_temp.act_as_db();
  select count(*) into n from sessions where course_id = c_test and is_active;
  report := report || pg_temp.chk('FR-24', 'only one active session for the course', n = 1, n::text);
  v := pg_temp.try_sql(format(
    'insert into public.sessions (course_id, qr_token, qr_expires_at) values (%L, %L, now())',
    c_test, 'TEST-DUP'));
  report := report || pg_temp.chk('FR-24', 'database blocks a 2nd active session (unique index)', v like 'ERROR%', v);

  perform pg_temp.act_as(adm);
  r := pg_temp.start(c_noslot);
  sess_adm := (r->>'session_id')::uuid;
  report := report || pg_temp.chk('FR-16', 'admin starts a course with no slot -> STARTED', r->>'code' = 'STARTED', r->>'code');

  -- ================= QR scans (mark_attendance) =================
  perform pg_temp.act_as(s1);
  v := pg_temp.scan(tok_a, 'TEST-PHONE-1');
  report := report || pg_temp.chk('FR-33', 'enrolled student, valid QR -> MARKED', v = 'MARKED', v);

  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-39', 'first scan binds TEST-PHONE-1 to student1',
    (select device_id from profiles where id = s1) = 'TEST-PHONE-1',
    (select device_id from profiles where id = s1));
  report := report || pg_temp.chk('FR-36', 'attendance saved for the scanned session + its course',
    exists (select 1 from attendance where student_id = s1 and session_id = sess_a and course_id = c_test),
    'no matching row');

  perform pg_temp.act_as(s1);
  v := pg_temp.scan(tok_a, 'TEST-PHONE-1');
  report := report || pg_temp.chk('FR-34', 'same student scans again -> already marked', v in ('DUPLICATE_ATTEMPT', 'ALREADY_MARKED'), v);

  perform pg_temp.act_as(s2);
  v := pg_temp.scan(tok_a, 'TEST-PHONE-1');
  report := report || pg_temp.chk('FR-41', 'student2 on student1''s phone, same session -> blocked',
    v in ('DEVICE_MULTI_STUDENT', 'DEVICE_ALREADY_BOUND', 'DEVICE_MISMATCH', 'DEVICE_BLOCKED'), v);

  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-41', 'blocked attempt created NO attendance row',
    not exists (select 1 from attendance where session_id = sess_a and student_id = s2), 'row exists');
  report := report || pg_temp.chk('FR-42', 'audit_logs: high, account = student2, phone owner = student1',
    exists (select 1 from audit_logs where session_id = sess_a and severity = 'high'
                                     and account_id = s2 and device_owner_id = s1), 'no such row');

  perform pg_temp.act_as(s3);
  v := pg_temp.scan(tok_a, 'TEST-PHONE-3');
  report := report || pg_temp.chk('FR-33', 'student not enrolled -> NOT_ENROLLED', v = 'NOT_ENROLLED', v);

  v := pg_temp.scan('NO-SUCH-TOKEN-123', 'TEST-PHONE-3');
  report := report || pg_temp.chk('FR-35', 'unknown QR token -> INVALID_QR', v = 'INVALID_QR', v);

  -- FR-26: refresh gives a new token
  perform pg_temp.act_as(t_a);
  r := pg_temp.call_jsonb(format('select to_jsonb(public.refresh_qr_token(%L::uuid))', sess_a));
  tok_new := r->>'token';
  report := report || pg_temp.chk('FR-26', 'refresh_qr_token returns a NEW token', tok_new is not null and tok_new <> tok_a, r::text);

  -- FR-35: expired token (old and new both expired)
  perform pg_temp.act_as_db();
  update sessions set qr_expires_at = now() - interval '1 minute',
                      qr_prev_expires_at = now() - interval '1 minute'
   where id = sess_a;
  perform pg_temp.act_as(s2);
  v := pg_temp.scan(tok_new, 'TEST-PHONE-2');
  report := report || pg_temp.chk('FR-35', 'expired QR -> INVALID_QR', v = 'INVALID_QR', v);

  -- FR-23: end the class
  perform pg_temp.act_as(t_a);
  r := pg_temp.call_jsonb(format('select to_jsonb(public.end_session(%L::uuid))', sess_a));
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-23', 'end_session -> session no longer active',
    (r->>'ok')::boolean and not (select is_active from sessions where id = sess_a), r::text);

  -- ================= Second class: own phone, then proxy =================
  perform pg_temp.act_as(t_a);
  r := pg_temp.start(c_test);
  sess_b := (r->>'session_id')::uuid; tok_b := r->>'token';

  perform pg_temp.act_as(s2);
  v := pg_temp.scan(tok_b, 'TEST-PHONE-2');
  report := report || pg_temp.chk('FR-40', 'student2 on own phone -> MARKED (phone bound)', v = 'MARKED', v);

  -- end and start again so student2 can try once more in a NEW class
  perform pg_temp.act_as(t_a);
  perform pg_temp.call_jsonb(format('select to_jsonb(public.end_session(%L::uuid))', sess_b));
  r := pg_temp.start(c_test);
  sess_b := (r->>'session_id')::uuid; tok_b := r->>'token';

  perform pg_temp.act_as(s2);
  v := pg_temp.scan(tok_b, 'TEST-PHONE-1');
  report := report || pg_temp.chk('FR-40', 'student2 logged in on student1''s phone -> blocked',
    v in ('DEVICE_MISMATCH', 'DEVICE_ALREADY_BOUND', 'DEVICE_BLOCKED'), v);

  perform pg_temp.act_as_db();
  select id into alert_id from audit_logs
   where session_id = sess_b and severity = 'high' and account_id = s2 and device_owner_id = s1
   limit 1;
  report := report || pg_temp.chk('FR-42', 'proxy attempt logged: high, both students', alert_id is not null, 'no such row');

  -- ================= Manual attendance =================
  perform pg_temp.act_as(t_a);
  r := pg_temp.call_jsonb(format('select to_jsonb(public.mark_manual(%L::uuid, %L::uuid))', sess_b, s1));
  report := report || pg_temp.chk('FR-28', 'teacher marks student1 manually -> MARKED', r->>'code' = 'MARKED', r::text);
  r := pg_temp.call_jsonb(format('select to_jsonb(public.mark_manual(%L::uuid, %L::uuid))', sess_b, s1));
  report := report || pg_temp.chk('FR-28', 'manual mark twice -> ALREADY_MARKED', r->>'code' = 'ALREADY_MARKED', r::text);
  perform pg_temp.act_as(t_b);
  r := pg_temp.call_jsonb(format('select to_jsonb(public.mark_manual(%L::uuid, %L::uuid))', sess_b, s2));
  report := report || pg_temp.chk('FR-28', 'other teacher cannot mark manually -> NOT_ALLOWED', r->>'code' = 'NOT_ALLOWED', r::text);
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-28', 'manual row: method manual, no device_id',
    exists (select 1 from attendance where session_id = sess_b and student_id = s1
                                      and method = 'manual' and device_id is null), 'no such row');

  -- ================= Alerts visibility (RLS) =================
  perform pg_temp.act_as(t_a);
  select count(*) into n from audit_logs where course_id = c_test;
  report := report || pg_temp.chk('FR-44', 'course teacher sees this course''s alerts', n > 0, n::text);

  v := pg_temp.try_sql(format('update public.audit_logs set is_read = true where id = %L', alert_id));
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-44', 'teacher can mark an alert as read',
    (select is_read from audit_logs where id = alert_id), v);

  perform pg_temp.act_as(t_a);
  v := pg_temp.try_sql(format('update public.audit_logs set severity = ''low'' where id = %L', alert_id));
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-44', 'teacher can NOT change other alert fields',
    (select severity from audit_logs where id = alert_id) = 'high', v);

  perform pg_temp.act_as(t_b);
  select count(*) into n from audit_logs where course_id = c_test;
  report := report || pg_temp.chk('FR-44', 'other teacher does NOT see these alerts', n = 0, n::text);

  perform pg_temp.act_as(adm);
  select count(*) into n from audit_logs where course_id = c_test;
  report := report || pg_temp.chk('FR-17', 'admin does NOT see proxy alerts (teacher only)', n = 0, n::text);

  perform pg_temp.act_as(s1);
  select count(*) into n from audit_logs where course_id = c_test;
  report := report || pg_temp.chk('FR-42', 'students can NOT read audit_logs', n = 0, n::text);

  -- ================= Server-only writes =================
  perform pg_temp.act_as(s1);
  v := pg_temp.try_sql(format(
    'insert into public.attendance (session_id, student_id, course_id, method) values (%L, %L, %L, ''qr'')',
    sess_b, s1, c_test));
  report := report || pg_temp.chk('FR-33', 'student can NOT insert attendance directly', v like 'ERROR%', v);
  v := pg_temp.try_sql(format(
    'insert into public.audit_logs (event_type, severity, account_id) values (''FAKE'', ''low'', %L)', s1));
  report := report || pg_temp.chk('FR-42', 'student can NOT write audit_logs directly', v like 'ERROR%', v);

  -- ================= Student records =================
  perform pg_temp.act_as(s1);
  select count(*) into n from public.get_my_attendance_summary()
   where course_id = c_test and attended_sessions >= 1;
  report := report || pg_temp.chk('FR-46', 'get_my_attendance_summary counts the test course', n = 1, n::text);
  select count(*) into n from public.get_my_course_history(c_test) where present;
  report := report || pg_temp.chk('FR-48', 'get_my_course_history shows Present rows', n >= 1, n::text);

  if to_regprocedure('public.get_my_last_attendance()') is null then
    report := report || pg_temp.chk('FR-38', 'get_my_last_attendance exists', false, 'not created (sql/last_attendance_info.sql not run)');
  else
    r := pg_temp.call_jsonb('select to_jsonb(x) from public.get_my_last_attendance() x');
    report := report || pg_temp.chk('FR-38', 'last attendance = ZZ-TEST, teacher Ashfaq Ahmed',
      r->>'course_code' = 'ZZ-TEST' and r->>'teacher_name' = 'Ashfaq Ahmed', r::text);
  end if;

  -- ================= Reset device =================
  perform pg_temp.act_as(s2);
  r := pg_temp.call_jsonb(format('select to_jsonb(public.reset_device(%L::uuid))', s1));
  report := report || pg_temp.chk('FR-45', 'a student can NOT reset another phone',
    coalesce((r->>'ok')::boolean, false) = false, r::text);

  perform pg_temp.act_as(t_a);
  r := pg_temp.call_jsonb(format('select to_jsonb(public.reset_device(%L::uuid))', s1));
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-45', 'teacher resets student1''s phone -> device_id empty',
    (r->>'ok')::boolean and (select device_id from profiles where id = s1) is null, r::text);

  -- ================= Structure checks =================
  perform pg_temp.act_as_db();
  report := report || pg_temp.chk('FR-18', 'timetable has rows', (select count(*) from timetable) > 1, null);
  report := report || pg_temp.chk('FR-7', 'courses.teacher_id may be empty (teacher removal)',
    (select is_nullable from information_schema.columns
      where table_schema = 'public' and table_name = 'courses' and column_name = 'teacher_id') = 'YES', 'NOT NULL');
  report := report || pg_temp.chk('FR-12', 'admin_delete_student exists (sql/admin_students.sql)',
    to_regprocedure('public.admin_delete_student(uuid)') is not null, 'not created');
  report := report || pg_temp.chk('FR-43', 'Realtime enabled on audit_logs',
    exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'audit_logs'), 'not in publication');
  report := report || pg_temp.chk('FR-27', 'Realtime enabled on attendance',
    exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'attendance'), 'not in publication');

  -- ---------- Finish: undo EVERYTHING ----------
  raise exception E'TEST REPORT (everything was rolled back)\nFAIL count: %\n%',
    (length(report) - length(replace(report, 'FAIL  ', ''))) / length('FAIL  '),
    report;
end $$;
