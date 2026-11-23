-- =====================================================================
-- Teachers + timetable + time-locked start_session   (BSE-5B)
--
-- Run this WHOLE file once in the Supabase SQL Editor.
-- It runs inside one transaction: if anything fails, NOTHING is changed.
-- Safe to run again later (for example after fixing an email).
--
-- BEFORE RUNNING: fill in the teacher emails in STEP 0 below.
-- =====================================================================

begin;

-- =====================================================================
-- STEP 0: teachers and their courses  >>> EDIT THE EMAILS HERE <<<
-- Each email must be exactly the email of the account you created in
-- Supabase Auth. Course codes CS-303 ... CS-307 / CS-304L are the codes
-- this project uses; change them here if your real codes differ.
-- =====================================================================
create temp table teacher_map (
  email       text,
  full_name   text,
  course_code text,
  course_name text
) on commit drop;

insert into teacher_map (email, full_name, course_code, course_name) values
  ('ashfaq@test.com',  'Ashfaq Ahmed',          'CS-301',  'Mobile App Development'),
  ('ashfaq@test.com',  'Ashfaq Ahmed',          'CS-301L', 'Mobile App Development (Lab)'),
  ('riaz@test.com',    'Riaz Ahmad',            'CS-303',  'Operating Systems'),
  ('riaz@test.com',    'Riaz Ahmad',            'CS-303L', 'Operating Systems (Lab)'),
  ('shahid@test.com',  'Muhammad Shahid Khan',  'CS-304',  'Web Technologies'),
  ('adil@test.com',    'Syed Adil Ibrar Kazmi', 'CS-304L', 'Web Technologies (Lab)'),
  ('sarah@test.com',   'Sarah Amjad',           'CS-305',  'Multivariable Calculus'),
  ('maira@test.com',   'Maira Afzal',           'CS-306',  'Software Design and Architecture'),
  ('areeba@test.com',  'Areeba Sadaqat',        'CS-307',  'Computer Organization and Assembly Language (COAL)'),
  ('areeba@test.com',  'Areeba Sadaqat',        'CS-307L', 'COAL (Lab)');

-- Stop everything if an email has no login account in Supabase Auth.
do $$
declare
  missing text;
begin
  select string_agg(m.email, ', ') into missing
  from teacher_map m
  where not exists (select 1 from auth.users u
                    where lower(u.email) = lower(m.email));
  if missing is not null then
    raise exception 'No Supabase Auth account for: %. Fix these emails in STEP 0, or create the accounts in Authentication > Users. Nothing was changed.', missing;
  end if;
end $$;


-- =====================================================================
-- STEP 1: make them teachers and set their names
-- =====================================================================
-- If an account has no profiles row yet (the signup trigger did not run),
-- create it from the Auth account.
insert into public.profiles (id, email, full_name, role)
select u.id, u.email, m.full_name, 'teacher'
from teacher_map m
join auth.users u on lower(u.email) = lower(m.email)
where not exists (select 1 from public.profiles p where p.id = u.id);

-- Existing profiles: set role and name.
update public.profiles p
set role = 'teacher',
    full_name = m.full_name
from teacher_map m
where lower(p.email) = lower(m.email);


-- =====================================================================
-- STEP 2: insert or update the courses with the right teacher
-- (CS-302 Database Systems is not on this timetable and is not touched.)
-- =====================================================================
-- Existing courses: set the name and the teacher.
update public.courses c
set name = m.course_name,
    teacher_id = p.id
from teacher_map m
join public.profiles p on lower(p.email) = lower(m.email)
where c.code = m.course_code;

-- Missing courses: create them (same semester as CS-301).
insert into public.courses (name, code, semester, teacher_id)
select m.course_name, m.course_code,
       (select semester from public.courses where code = 'CS-301'),
       p.id
from teacher_map m
join public.profiles p on lower(p.email) = lower(m.email)
where not exists (select 1 from public.courses c where c.code = m.course_code);

-- Test students: enroll in every timetable course (existing ones are skipped).
insert into public.enrollments (student_id, course_id)
select s.id, c.id
from public.profiles s
cross join public.courses c
where s.email in ('student1@test.com', 'student2@test.com', 'student3@test.com')
  and c.code in (select course_code from teacher_map)
on conflict (student_id, course_id) do nothing;


-- =====================================================================
-- STEP 3: timetable table + RLS + the timetable rows
-- day_of_week: 1 = Monday ... 7 = Sunday.  Times are Pakistan time.
-- =====================================================================
create table if not exists public.timetable (
  id          uuid primary key default gen_random_uuid(),
  course_id   uuid not null references public.courses(id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 1 and 7),
  start_time  time not null,
  end_time    time not null,
  check (end_time > start_time),
  unique (course_id, day_of_week, start_time)
);

create index if not exists timetable_course_id_idx on public.timetable(course_id);

alter table public.timetable enable row level security;

-- READ: admin all; teacher their own courses; student their enrolled courses.
drop policy if exists "timetable_read_own" on public.timetable;
create policy "timetable_read_own" on public.timetable
  for select to authenticated
  using (
    exists (select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin')
    or exists (select 1 from public.courses c
               where c.id = timetable.course_id and c.teacher_id = auth.uid())
    or exists (select 1 from public.enrollments e
               where e.course_id = timetable.course_id and e.student_id = auth.uid())
  );

-- INSERT / UPDATE / DELETE: admin only.
drop policy if exists "timetable_admin_manage" on public.timetable;
create policy "timetable_admin_manage" on public.timetable
  for all to authenticated
  using (exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin'))
  with check (exists (select 1 from public.profiles p
                      where p.id = auth.uid() and p.role = 'admin'));

-- Replace the whole timetable with the BSE-5B timetable.
-- (Only timetable rows are removed — no courses, sessions or attendance.)
delete from public.timetable;

insert into public.timetable (course_id, day_of_week, start_time, end_time)
select c.id, v.day_of_week, v.start_time::time, v.end_time::time
from (values
  ('CS-301L', 1, '08:30', '11:30'),  -- Mon  Mobile App. Dev. (Lab)     Ashfaq Ahmed
  ('CS-303L', 1, '13:30', '16:30'),  -- Mon  Operating Systems (Lab)    Riaz Ahmad
  ('CS-304',  2, '11:00', '13:00'),  -- Tue  Web Technologies           Muhammad Shahid Khan
  ('CS-304L', 2, '13:30', '16:30'),  -- Tue  Web Technologies (Lab)     Syed Adil Ibrar Kazmi
  ('CS-305',  3, '09:30', '11:00'),  -- Wed  Multivariable Calculus     Sarah Amjad
  ('CS-301',  3, '11:00', '13:00'),  -- Wed  Mobile App. Dev.           Ashfaq Ahmed
  ('CS-306',  4, '08:30', '10:00'),  -- Thu  Software Design and Arch.  Maira Afzal
  ('CS-305',  4, '10:00', '11:30'),  -- Thu  Multivariable Calculus     Sarah Amjad
  ('CS-307L', 4, '13:30', '16:30'),  -- Thu  COAL (Lab)                 Areeba Sadaqat
  ('CS-303',  5, '09:30', '11:30'),  -- Fri  Operating Systems          Riaz Ahmad
  ('CS-306',  5, '11:30', '13:00'),  -- Fri  Software Design and Arch.  Maira Afzal
  ('CS-307',  5, '14:30', '16:30')   -- Fri  COAL                       Areeba Sadaqat
) as v(code, day_of_week, start_time, end_time)
join public.courses c on c.code = v.code;


-- =====================================================================
-- STEP 4: time-lock start_session (FR-16)
-- Replaces the existing start_session (no rename, no wrapper).
-- Same code as sql/start_session_timelock.sql - keep the two identical.
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

commit;

-- Make the API see the changes immediately.
notify pgrst, 'reload schema';


-- =====================================================================
-- CHECK: teachers, their courses and the timetable (12 rows)
-- =====================================================================
select c.code, c.name, p.full_name as teacher, p.email,
       t.day_of_week, t.start_time, t.end_time
from public.timetable t
join public.courses c on c.id = t.course_id
join public.profiles p on p.id = c.teacher_id
order by t.day_of_week, t.start_time;
