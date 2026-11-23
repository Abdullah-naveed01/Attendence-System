-- =====================================================================
-- Phase 1 d) - Server test of mark_attendance (FR-28 to FR-35)
--
-- SAFE: nothing is kept. The whole test is one DO block, and it ENDS
-- WITH AN ERROR on purpose. In PostgreSQL an error undoes everything
-- the block did, so the test course, sessions, attendance rows,
-- audit_logs rows and device changes all disappear.
--
-- How to read the result: the "error" message at the end IS the test
-- report. Every line says PASS or FAIL. Look for:
--     TEST REPORT (everything was rolled back)
--
-- How it works:
--   - pretends to be a student by setting request.jwt.claim.sub
--     (this is what auth.uid() reads), then calls the REAL
--     mark_attendance function exactly like the app does
--   - uses a temporary course ZZ-TEST: student1 + student2 enrolled,
--     student3 NOT enrolled
--   - uses fake phone IDs TEST-PHONE-1/2/3 (real device bindings are
--     cleared only inside the test and come back after the rollback)
--
-- Server code -> what the app shows:
--   MARKED                                   -> Attendance Marked
--   DUPLICATE_ATTEMPT                        -> Already Marked
--   DEVICE_MULTI_STUDENT / DEVICE_ALREADY_BOUND /
--   DEVICE_MISMATCH                          -> Device Blocked
--   INVALID_QR                               -> QR expired
--   NOT_ENROLLED                             -> Not Enrolled
-- =====================================================================

-- Helper used only by this test: "student X scans token T on phone D".
-- It is created in pg_temp (a private, temporary schema) and is removed
-- by the rollback at the end as well.
create function pg_temp.scan(p_student uuid, p_token text, p_device text)
returns text
language plpgsql
as $$
begin
  -- Pretend to be this student (same as being logged in on the phone)
  perform set_config('request.jwt.claim.sub', p_student::text, true);
  return public.mark_attendance(p_token, p_device) ->> 'code';
end;
$$;

do $$
declare
  s1 uuid;  s2 uuid;  s3 uuid;  t uuid;          -- students + teacher
  v_course uuid;
  v_sess_a uuid;  v_sess_b uuid;  v_sess_c uuid;
  v_code   text;
  report   text := '';
  fails    int  := 0;
begin
  select id into s1 from profiles where email = 'student1@test.com';
  select id into s2 from profiles where email = 'student2@test.com';
  select id into s3 from profiles where email = 'student3@test.com';
  select id into t  from profiles where email = 'teacher@test.com';
  if s1 is null or s2 is null or s3 is null or t is null then
    raise exception 'Test users are missing (student1/2/3, teacher). Nothing was changed.';
  end if;

  -- ---------- Setup (all undone at the end) ----------
  update profiles set device_id = null where id in (s1, s2, s3);

  insert into courses (name, code, semester, teacher_id)
  values ('Test Course', 'ZZ-TEST', 'TEST', t)
  returning id into v_course;

  insert into enrollments (student_id, course_id)
  values (s1, v_course), (s2, v_course);          -- student3 NOT enrolled

  insert into sessions (course_id, qr_token, qr_expires_at)
  values (v_course, 'TEST-TOKEN-A', now() + interval '30 seconds')
  returning id into v_sess_a;

  -- ---------- Session A ----------
  -- 1. Valid scan
  v_code := pg_temp.scan(s1, 'TEST-TOKEN-A', 'TEST-PHONE-1');
  if v_code = 'MARKED' then report := report || E'\nPASS  1 valid scan -> MARKED';
  else fails := fails + 1; report := report || E'\nFAIL  1 valid scan, expected MARKED, got ' || coalesce(v_code, 'null'); end if;

  -- 1b. First scan binds the phone to student1
  if (select device_id from profiles where id = s1) = 'TEST-PHONE-1'
  then report := report || E'\nPASS  1b phone TEST-PHONE-1 is now bound to student1';
  else fails := fails + 1; report := report || E'\nFAIL  1b phone was not bound to student1'; end if;

  -- 2. Same student scans again
  v_code := pg_temp.scan(s1, 'TEST-TOKEN-A', 'TEST-PHONE-1');
  if v_code = 'DUPLICATE_ATTEMPT' then report := report || E'\nPASS  2 second scan -> DUPLICATE_ATTEMPT (app: Already Marked)';
  else fails := fails + 1; report := report || E'\nFAIL  2 second scan, expected DUPLICATE_ATTEMPT, got ' || coalesce(v_code, 'null'); end if;

  -- 3. student2 uses student1's phone in the same session
  v_code := pg_temp.scan(s2, 'TEST-TOKEN-A', 'TEST-PHONE-1');
  if v_code = 'DEVICE_MULTI_STUDENT' then report := report || E'\nPASS  3 student2 on student1''s phone -> DEVICE_MULTI_STUDENT (app: Device Blocked)';
  else fails := fails + 1; report := report || E'\nFAIL  3 expected DEVICE_MULTI_STUDENT, got ' || coalesce(v_code, 'null'); end if;

  if exists (select 1 from audit_logs
             where session_id = v_sess_a and event_type = 'DEVICE_MULTI_STUDENT'
               and severity = 'high' and account_id = s2 and device_owner_id = s1)
  then report := report || E'\nPASS  3b audit_logs: high, account_id = student2, device_owner_id = student1';
  else fails := fails + 1; report := report || E'\nFAIL  3b no high audit row with both student IDs'; end if;

  -- 4. Not enrolled student
  v_code := pg_temp.scan(s3, 'TEST-TOKEN-A', 'TEST-PHONE-3');
  if v_code = 'NOT_ENROLLED' then report := report || E'\nPASS  4 student3 (not enrolled) -> NOT_ENROLLED';
  else fails := fails + 1; report := report || E'\nFAIL  4 expected NOT_ENROLLED, got ' || coalesce(v_code, 'null'); end if;

  -- 5. Expired token (expiry moved into the past)
  update sessions set qr_expires_at = now() - interval '1 second' where id = v_sess_a;
  v_code := pg_temp.scan(s2, 'TEST-TOKEN-A', 'TEST-PHONE-2');
  if v_code = 'INVALID_QR' then report := report || E'\nPASS  5 expired token -> INVALID_QR';
  else fails := fails + 1; report := report || E'\nFAIL  5 expected INVALID_QR, got ' || coalesce(v_code, 'null'); end if;

  -- 5b. Unknown token
  v_code := pg_temp.scan(s2, 'NO-SUCH-TOKEN', 'TEST-PHONE-2');
  if v_code = 'INVALID_QR' then report := report || E'\nPASS  5b unknown token -> INVALID_QR';
  else fails := fails + 1; report := report || E'\nFAIL  5b expected INVALID_QR, got ' || coalesce(v_code, 'null'); end if;

  -- ---------- Session B (A ended) ----------
  update sessions set is_active = false, ended_at = now() where id = v_sess_a;
  insert into sessions (course_id, qr_token, qr_expires_at)
  values (v_course, 'TEST-TOKEN-B', now() + interval '30 seconds')
  returning id into v_sess_b;

  -- 6. student2 (no phone yet) tries student1's registered phone
  v_code := pg_temp.scan(s2, 'TEST-TOKEN-B', 'TEST-PHONE-1');
  if v_code = 'DEVICE_ALREADY_BOUND' then report := report || E'\nPASS  6 student2 on a phone registered to student1 -> DEVICE_ALREADY_BOUND (app: Device Blocked)';
  else fails := fails + 1; report := report || E'\nFAIL  6 expected DEVICE_ALREADY_BOUND, got ' || coalesce(v_code, 'null'); end if;

  if exists (select 1 from audit_logs
             where session_id = v_sess_b and event_type = 'DEVICE_ALREADY_BOUND'
               and severity = 'high' and account_id = s2 and device_owner_id = s1)
  then report := report || E'\nPASS  6b audit_logs: high, account_id = student2, device_owner_id = student1';
  else fails := fails + 1; report := report || E'\nFAIL  6b no high audit row with both student IDs'; end if;

  -- 7. student2 on their own phone
  v_code := pg_temp.scan(s2, 'TEST-TOKEN-B', 'TEST-PHONE-2');
  if v_code = 'MARKED' then report := report || E'\nPASS  7 student2 on own phone -> MARKED (phone TEST-PHONE-2 bound)';
  else fails := fails + 1; report := report || E'\nFAIL  7 expected MARKED, got ' || coalesce(v_code, 'null'); end if;

  -- ---------- Session C: the viva proxy demo ----------
  update sessions set is_active = false, ended_at = now() where id = v_sess_b;
  insert into sessions (course_id, qr_token, qr_expires_at)
  values (v_course, 'TEST-TOKEN-C', now() + interval '30 seconds')
  returning id into v_sess_c;

  -- 8. student2 (has own phone) logs in on student1's phone, student1 not scanned yet
  v_code := pg_temp.scan(s2, 'TEST-TOKEN-C', 'TEST-PHONE-1');
  if v_code = 'DEVICE_MISMATCH' then report := report || E'\nPASS  8 student2 logged in on student1''s phone -> DEVICE_MISMATCH (app: Device Blocked)';
  else fails := fails + 1; report := report || E'\nFAIL  8 expected DEVICE_MISMATCH, got ' || coalesce(v_code, 'null'); end if;

  if exists (select 1 from audit_logs
             where session_id = v_sess_c and event_type = 'DEVICE_MISMATCH'
               and severity = 'high' and account_id = s2 and device_owner_id = s1)
  then report := report || E'\nPASS  8b audit_logs: high, account_id = student2, device_owner_id = student1';
  else fails := fails + 1; report := report || E'\nFAIL  8b no high audit row with both student IDs'; end if;

  -- 9. The blocked attempt did NOT create attendance; student1 can still mark
  if not exists (select 1 from attendance where session_id = v_sess_c and student_id = s2)
  then report := report || E'\nPASS  9 no attendance row was created for the blocked attempt';
  else fails := fails + 1; report := report || E'\nFAIL  9 a blocked attempt created attendance'; end if;

  v_code := pg_temp.scan(s1, 'TEST-TOKEN-C', 'TEST-PHONE-1');
  if v_code = 'MARKED' then report := report || E'\nPASS  9b real owner student1 can still mark -> MARKED';
  else fails := fails + 1; report := report || E'\nFAIL  9b expected MARKED, got ' || coalesce(v_code, 'null'); end if;

  -- ---------- Finish: undo EVERYTHING ----------
  raise exception E'TEST REPORT (everything was rolled back)\n% of 15 checks failed%',
    fails, report;
end $$;
