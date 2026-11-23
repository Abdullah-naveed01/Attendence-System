-- =====================================================================
-- Split every lab into its own course (separate Start Class and
-- separate attendance for the lab and the lecture).
--
--   CS-301L  Mobile App Development (Lab)   Mon 08:30-11:30   Ashfaq Ahmed
--   CS-303L  Operating Systems (Lab)        Mon 13:30-16:30   Riaz Ahmad
--   CS-304L  Web Technologies (Lab)         Tue 13:30-16:30   Syed Adil Ibrar Kazmi (already exists)
--   CS-307L  COAL (Lab)                     Thu 13:30-16:30   Areeba Sadaqat
--
-- For each lab:
--   1. create the lab course (same semester as its lecture) for its teacher
--   2. move the lab's timetable slot from the lecture to the lab course
--   3. enroll every student of the lecture in the lab
--
-- One transaction: if anything fails, NOTHING is changed.
-- Safe to run more than once.
-- Old sessions and attendance stay with the lecture course (not moved).
-- =====================================================================

begin;

create temp table lab_map (
  lab_code      text,
  lab_name      text,
  lecture_code  text,
  teacher_email text,
  day_of_week   smallint,
  start_time    time
) on commit drop;

insert into lab_map values
  ('CS-301L', 'Mobile App Development (Lab)', 'CS-301', 'ashfaq@test.com', 1, '08:30'),
  ('CS-303L', 'Operating Systems (Lab)',      'CS-303', 'riaz@test.com',   1, '13:30'),
  ('CS-304L', 'Web Technologies (Lab)',       'CS-304', 'adil@test.com',   2, '13:30'),
  ('CS-307L', 'COAL (Lab)',                   'CS-307', 'areeba@test.com', 4, '13:30');

-- Safety check: every lecture course and every teacher must exist.
do $$
declare
  missing text;
begin
  select string_agg(m.lecture_code || ' / ' || m.teacher_email, ', ') into missing
  from lab_map m
  where not exists (select 1 from public.courses c where c.code = m.lecture_code)
     or not exists (select 1 from public.profiles p
                    where lower(p.email) = lower(m.teacher_email) and p.role = 'teacher');
  if missing is not null then
    raise exception 'Missing course or teacher: %. Nothing was changed.', missing;
  end if;
end $$;

-- 1) Create the lab courses that do not exist yet
insert into public.courses (name, code, semester, teacher_id)
select m.lab_name, m.lab_code, lecture.semester, p.id
from lab_map m
join public.courses lecture on lecture.code = m.lecture_code
join public.profiles p on lower(p.email) = lower(m.teacher_email)
where not exists (select 1 from public.courses c where c.code = m.lab_code);

-- ...and make sure each lab belongs to its teacher
update public.courses c
set teacher_id = p.id
from lab_map m
join public.profiles p on lower(p.email) = lower(m.teacher_email)
where c.code = m.lab_code;

-- 2) Move the lab slot from the lecture course to the lab course
update public.timetable t
set course_id = lab.id
from lab_map m
join public.courses lecture on lecture.code = m.lecture_code
join public.courses lab on lab.code = m.lab_code
where t.course_id = lecture.id
  and t.day_of_week = m.day_of_week
  and t.start_time = m.start_time;

-- 3) Students of the lecture also take its lab
insert into public.enrollments (student_id, course_id)
select e.student_id, lab.id
from lab_map m
join public.courses lecture on lecture.code = m.lecture_code
join public.courses lab on lab.code = m.lab_code
join public.enrollments e on e.course_id = lecture.id
on conflict (student_id, course_id) do nothing;

commit;

-- =====================================================================
-- CHECK (read-only): every course, its teacher and its weekly slots
-- =====================================================================
select c.code,
       c.name,
       p.full_name as teacher,
       coalesce(string_agg(
         (array['Mon','Tue','Wed','Thu','Fri','Sat','Sun'])[t.day_of_week]
           || ' ' || to_char(t.start_time, 'HH24:MI')
           || '-' || to_char(t.end_time, 'HH24:MI'),
         ', ' order by t.day_of_week, t.start_time), '-') as schedule
from public.courses c
left join public.profiles p on p.id = c.teacher_id
left join public.timetable t on t.course_id = c.id
group by c.id, c.code, c.name, p.full_name
order by c.code;
