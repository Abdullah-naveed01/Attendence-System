-- =====================================================================
-- Phase 3 - Server test of mark_manual. SAFE: ends with an error on
-- purpose, so everything it did is rolled back. The error text is the
-- PASS/FAIL report. Run AFTER sql/mark_manual.sql.
--
-- Temporary course ZZ-TEST (teacher = teacher@test.com),
-- student1 enrolled, student2 NOT enrolled.
-- =====================================================================

create function pg_temp.manual(p_caller uuid, p_session uuid, p_student uuid)
returns text
language plpgsql
as $$
begin
  -- Pretend to be this user (what auth.uid() reads)
  perform set_config('request.jwt.claim.sub', p_caller::text, true);
  return public.mark_manual(p_session, p_student) ->> 'code';
end;
$$;

do $$
declare
  s1 uuid;  s2 uuid;  t uuid;  other_t uuid;
  v_course uuid;  v_sess uuid;
  v_code text;
  report text := '';
  fails  int  := 0;
begin
  select id into s1 from profiles where email = 'student1@test.com';
  select id into s2 from profiles where email = 'student2@test.com';
  select id into t  from profiles where email = 'teacher@test.com';
  select id into other_t from profiles where email = 'riaz@test.com';
  if s1 is null or s2 is null or t is null or other_t is null then
    raise exception 'Test users are missing. Nothing was changed.';
  end if;

  insert into courses (name, code, semester, teacher_id)
  values ('Test Course', 'ZZ-TEST', 'TEST', t) returning id into v_course;
  insert into enrollments (student_id, course_id) values (s1, v_course);
  insert into sessions (course_id, qr_token, qr_expires_at)
  values (v_course, 'TEST-TOKEN-M', now() + interval '30 seconds')
  returning id into v_sess;

  -- 1. Another teacher may not mark in this course
  v_code := pg_temp.manual(other_t, v_sess, s1);
  if v_code = 'NOT_ALLOWED' then report := report || E'\nPASS  1 other teacher -> NOT_ALLOWED';
  else fails := fails + 1; report := report || E'\nFAIL  1 expected NOT_ALLOWED, got ' || coalesce(v_code, 'null'); end if;

  -- 2. A student may not mark anyone
  v_code := pg_temp.manual(s1, v_sess, s1);
  if v_code = 'NOT_ALLOWED' then report := report || E'\nPASS  2 student calling it -> NOT_ALLOWED';
  else fails := fails + 1; report := report || E'\nFAIL  2 expected NOT_ALLOWED, got ' || coalesce(v_code, 'null'); end if;

  -- 3. Not enrolled student
  v_code := pg_temp.manual(t, v_sess, s2);
  if v_code = 'NOT_ENROLLED' then report := report || E'\nPASS  3 student2 not enrolled -> NOT_ENROLLED';
  else fails := fails + 1; report := report || E'\nFAIL  3 expected NOT_ENROLLED, got ' || coalesce(v_code, 'null'); end if;

  -- 4. Course teacher marks student1
  v_code := pg_temp.manual(t, v_sess, s1);
  if v_code = 'MARKED' then report := report || E'\nPASS  4 teacher marks student1 -> MARKED';
  else fails := fails + 1; report := report || E'\nFAIL  4 expected MARKED, got ' || coalesce(v_code, 'null'); end if;

  -- 4b. The row is manual, present, and has no phone
  if exists (select 1 from attendance
             where session_id = v_sess and student_id = s1
               and method = 'manual' and device_id is null and status = 'present')
  then report := report || E'\nPASS  4b row: method manual, device_id NULL, status present';
  else fails := fails + 1; report := report || E'\nFAIL  4b row is not manual/null device/present'; end if;

  -- 5. Marking again
  v_code := pg_temp.manual(t, v_sess, s1);
  if v_code = 'ALREADY_MARKED' then report := report || E'\nPASS  5 mark again -> ALREADY_MARKED';
  else fails := fails + 1; report := report || E'\nFAIL  5 expected ALREADY_MARKED, got ' || coalesce(v_code, 'null'); end if;

  -- 6. Ended class
  update sessions set is_active = false, ended_at = now() where id = v_sess;
  v_code := pg_temp.manual(t, v_sess, s1);
  if v_code = 'SESSION_NOT_ACTIVE' then report := report || E'\nPASS  6 ended class -> SESSION_NOT_ACTIVE';
  else fails := fails + 1; report := report || E'\nFAIL  6 expected SESSION_NOT_ACTIVE, got ' || coalesce(v_code, 'null'); end if;

  raise exception E'TEST REPORT (everything was rolled back)\n% of 7 checks failed%',
    fails, report;
end $$;
