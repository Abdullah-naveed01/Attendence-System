-- =====================================================================
-- Fix: the 7 new accounts are TEACHERS, not students.
--   1. role = 'teacher' + correct full_name
--   2. remove any student enrollments they have
--   3. each course belongs to the teacher who teaches it (timetable)
--
-- One transaction: if anything fails, NOTHING is changed.
-- Safe to run more than once.
-- It does NOT touch: students, sessions, attendance, audit logs,
-- device IDs, CS-302, or the start_session function.
-- =====================================================================

begin;

-- Who teaches what (from the BSE-5B timetable)
create temp table teacher_map (
  email       text,
  full_name   text,
  course_code text,
  course_name text
) on commit drop;

insert into teacher_map (email, full_name, course_code, course_name) values
  ('ashfaq@test.com',  'Ashfaq Ahmed',          'CS-301',  'Mobile App Development'),
  ('riaz@test.com',    'Riaz Ahmad',            'CS-303',  'Operating Systems'),
  ('shahid@test.com',  'Muhammad Shahid Khan',  'CS-304',  'Web Technologies'),
  ('adil@test.com',    'Syed Adil Ibrar Kazmi', 'CS-304L', 'Web Technologies (Lab)'),
  ('sarah@test.com',   'Sarah Amjad',           'CS-305',  'Multivariable Calculus'),
  ('maira@test.com',   'Maira Afzal',           'CS-306',  'Software Design and Architecture'),
  ('areeba@test.com',  'Areeba Sadaqat',        'CS-307',  'Computer Organization and Assembly Language (COAL)');

-- Safety check: stop if any of the 7 emails has no profile.
do $$
declare
  missing text;
begin
  select string_agg(m.email, ', ') into missing
  from teacher_map m
  where not exists (select 1 from public.profiles p
                    where lower(p.email) = lower(m.email));
  if missing is not null then
    raise exception 'No profile for: %. Nothing was changed.', missing;
  end if;
end $$;

-- 1) Make them teachers with their real names
update public.profiles p
set role = 'teacher',
    full_name = m.full_name
from teacher_map m
where lower(p.email) = lower(m.email);

-- 2) Teachers are not students: remove any enrollments they have
delete from public.enrollments e
using public.profiles p
where e.student_id = p.id
  and lower(p.email) in (select lower(email) from teacher_map);

-- 3a) Web Technologies (Lab) has a different teacher than the lecture,
--     so it needs its own course. Create it if it does not exist.
insert into public.courses (name, code, semester, teacher_id)
select m.course_name, m.course_code,
       (select semester from public.courses where code = 'CS-301'),
       p.id
from teacher_map m
join public.profiles p on lower(p.email) = lower(m.email)
where m.course_code = 'CS-304L'
  and not exists (select 1 from public.courses c where c.code = 'CS-304L');

-- 3b) Give every course to its teacher
update public.courses c
set teacher_id = p.id
from teacher_map m
join public.profiles p on lower(p.email) = lower(m.email)
where c.code = m.course_code;

-- 3c) The Tuesday 13:30 lab slot belongs to the new lab course
update public.timetable t
set course_id = (select id from public.courses where code = 'CS-304L')
where t.course_id = (select id from public.courses where code = 'CS-304')
  and t.day_of_week = 2
  and t.start_time = '13:30';

-- 3d) The 3 test students keep the lab: enroll them in CS-304L
insert into public.enrollments (student_id, course_id)
select s.id, c.id
from public.profiles s
cross join public.courses c
where s.email in ('student1@test.com', 'student2@test.com', 'student3@test.com')
  and c.code = 'CS-304L'
on conflict (student_id, course_id) do nothing;

commit;

-- =====================================================================
-- CHECK (read-only): every teacher, their role and the courses they own
-- =====================================================================
select p.full_name as teacher,
       p.email,
       p.role,
       coalesce(string_agg(c.code, ', ' order by c.code), '-') as courses
from public.profiles p
left join public.courses c on c.teacher_id = p.id
where p.role = 'teacher'
group by p.id, p.full_name, p.email, p.role
order by p.full_name;
