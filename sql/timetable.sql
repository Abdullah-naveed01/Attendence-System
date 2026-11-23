-- =====================================================================
-- Class timetable (BSE-5B)
-- Run in the Supabase SQL Editor. Run PART 1, then (optionally) PART 2,
-- then PART 3. You can also paste all three parts and run them together.
--
-- day_of_week: 1 = Monday ... 7 = Sunday (same numbering as Dart's DateTime.weekday)
-- start_time / end_time: local class times (no time zone), e.g. 08:30
-- =====================================================================


-- =====================================================================
-- PART 1 (required): the table + Row Level Security
-- =====================================================================
create table if not exists public.timetable (
  id          uuid primary key default gen_random_uuid(),
  course_id   uuid not null references public.courses(id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 1 and 7),
  start_time  time not null,
  end_time    time not null,
  check (end_time > start_time),
  -- the same course cannot start twice at the same time on the same day
  unique (course_id, day_of_week, start_time)
);

create index if not exists timetable_course_id_idx on public.timetable(course_id);

alter table public.timetable enable row level security;

-- READ: admin sees everything, a teacher sees their own courses,
--       a student sees the courses they are enrolled in.
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


-- =====================================================================
-- PART 2 (optional, for the demo): add the courses that are on the
-- timetable but not in the database yet.
--
-- Your database has CS-301 Mobile App Development (on the timetable) and
-- CS-302 Database Systems (NOT on the timetable).
-- The codes below (CS-303 ... CS-307) are PLACEHOLDERS — change them to
-- your real course codes if you like (change them in PART 3 too).
--
-- All new courses get teacher@test.com as the teacher and the same
-- semester as CS-301, and the 3 test students are enrolled.
-- Safe to run twice: existing codes and enrollments are skipped.
-- =====================================================================
insert into public.courses (name, code, semester, teacher_id)
select v.name, v.code, base.semester, t.id
from (values
  ('Operating Systems',                         'CS-303'),
  ('Web Technologies',                          'CS-304'),
  ('Multivariable Calculus',                    'CS-305'),
  ('Software Design and Architecture',          'CS-306'),
  ('Computer Organization and Assembly Language (COAL)', 'CS-307')
) as v(name, code)
cross join (select semester from public.courses where code = 'CS-301') as base
cross join (select id from public.profiles where email = 'teacher@test.com') as t
where not exists (select 1 from public.courses c where c.code = v.code);

insert into public.enrollments (student_id, course_id)
select p.id, c.id
from public.profiles p
cross join public.courses c
where p.email in ('student1@test.com', 'student2@test.com', 'student3@test.com')
  and c.code in ('CS-303', 'CS-304', 'CS-305', 'CS-306', 'CS-307')
on conflict (student_id, course_id) do nothing;


-- =====================================================================
-- PART 3: the BSE-5B timetable
-- Rows are matched by course code. A row whose course does not exist is
-- simply skipped (so without PART 2, only the CS-301 rows are added).
-- Labs and lectures of the same subject use the same course.
-- Safe to run twice: duplicates are skipped.
-- =====================================================================
insert into public.timetable (course_id, day_of_week, start_time, end_time)
select c.id, v.day_of_week, v.start_time::time, v.end_time::time
from (values
  -- Monday
  ('CS-301', 1, '08:30', '11:30'),  -- Mobile App. Dev. (Lab)      Lab-3
  ('CS-303', 1, '13:30', '16:30'),  -- Operating Systems (Lab)     Lab-11 (G-07)
  -- Tuesday
  ('CS-304', 2, '11:00', '13:00'),  -- Web Technologies             G-08
  ('CS-304', 2, '13:30', '16:30'),  -- Web Technologies (Lab)       Lab-5
  -- Wednesday
  ('CS-305', 3, '09:30', '11:00'),  -- Multivariable Calculus       F-09
  ('CS-301', 3, '11:00', '13:00'),  -- Mobile App. Dev.             411
  -- Thursday
  ('CS-306', 4, '08:30', '10:00'),  -- Software Design and Arch.    F-01
  ('CS-305', 4, '10:00', '11:30'),  -- Multivariable Calculus       501
  ('CS-307', 4, '13:30', '16:30'),  -- COAL (Lab)                   Lab-5
  -- Friday
  ('CS-303', 5, '09:30', '11:30'),  -- Operating Systems            G-09
  ('CS-306', 5, '11:30', '13:00'),  -- Software Design and Arch.    F-05
  ('CS-307', 5, '14:30', '16:30')   -- COAL                         G-06
) as v(code, day_of_week, start_time, end_time)
join public.courses c on c.code = v.code
on conflict (course_id, day_of_week, start_time) do nothing;

-- Make the API see the new table immediately.
notify pgrst, 'reload schema';

-- Check: should list the timetable (12 rows with PART 2, 2 rows without it)
select c.code, c.name, t.day_of_week, t.start_time, t.end_time
from public.timetable t join public.courses c on c.id = t.course_id
order by t.day_of_week, t.start_time;
