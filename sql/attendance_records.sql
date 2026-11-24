-- =====================================================================
-- ATTENDANCE RECORDS (teacher) + per-course days (student)
-- One entry per course per day (Asia/Karachi date) everywhere.
--
-- Run the WHOLE file once in the Supabase SQL Editor.
-- One transaction: if anything fails, NOTHING is changed.
-- (This file replaces sql/daily_attendance.sql, which was never run.)
--
-- Statuses for a student on a class day:
--   present  - attended
--   late     - attended, but late          (set by the teacher)
--   excused  - did not attend, excused     (set by the teacher)
--   absent   - did not attend
--   in_progress - not marked yet while today's class is still running
-- Percentage: attended = present + late
--             counted  = present + late + absent
--             (excused days and a running class are not counted)
--
-- What this file does:
--   1. attendance: allow late/excused; add edited_by, edited_at,
--      edit_reason; remove an unneeded TRUNCATE right
--   2. view student_daily_attendance   (one row per student/course/day)
--   3. view attendance_summary         (same columns, day-based)
--   4. student functions (same result columns as before):
--        get_my_attendance_summary(), get_my_course_history(course)
--      + NEW get_my_course_days(course)     date-wise list with status
--   5. teacher functions (course teacher or admin only):
--        get_course_class_days(course)      dates + "Present X / Y"
--        get_course_day_records(course, date) every enrolled student
--        edit_attendance(session, student, status, reason)
-- Attendance rows are NEVER deleted: editing only updates the status
-- (or adds a manual row when a student had none that day).
-- Students can never edit: the app has no write rights on attendance,
-- and edit_attendance checks the role.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. attendance table
-- ---------------------------------------------------------------------
alter table public.attendance
  add column if not exists edited_by   uuid references public.profiles(id) on delete set null,
  add column if not exists edited_at   timestamptz,
  add column if not exists edit_reason text check (edit_reason is null or length(edit_reason) <= 500);

-- Replace the old status check ('present','absent') with the 4 statuses
do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.attendance'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format('alter table public.attendance drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.attendance
  add constraint attendance_status_check
  check (status in ('present', 'late', 'absent', 'excused'));

-- The app only READS attendance; writing is done by server functions.
revoke truncate on public.attendance from anon, authenticated;


-- ---------------------------------------------------------------------
-- 2. One row per student, course and day
-- ---------------------------------------------------------------------
create or replace view public.student_daily_attendance
with (security_invoker = true) as
with course_days as (
  -- every day a course had at least one session
  select s.course_id,
         (s.started_at at time zone 'Asia/Karachi')::date as class_date,
         (array_agg(s.id order by s.started_at))[1]        as first_session_id,
         min(s.started_at)                                 as first_started_at,
         bool_or(s.is_active)                              as is_active,
         case when bool_or(s.is_active) then null
              else max(s.ended_at) end                     as last_ended_at
  from public.sessions s
  group by s.course_id, (s.started_at at time zone 'Asia/Karachi')::date
),
day_rows as (
  -- the student's best row for that course and day, from ANY session
  -- (present > late > excused > absent; then QR; then the earliest)
  select distinct on (a.student_id, s.course_id,
                      (s.started_at at time zone 'Asia/Karachi')::date)
         a.student_id,
         s.course_id,
         (s.started_at at time zone 'Asia/Karachi')::date as class_date,
         a.status, a.method, a.marked_at,
         a.edited_by, a.edited_at, a.edit_reason
  from public.attendance a
  join public.sessions s on s.id = a.session_id
  order by a.student_id, s.course_id,
           (s.started_at at time zone 'Asia/Karachi')::date,
           case a.status when 'present' then 1 when 'late' then 2
                         when 'excused' then 3 else 4 end,
           (a.method = 'qr') desc,
           a.marked_at
)
select e.student_id,
       d.course_id,
       d.class_date,
       d.first_session_id,
       d.first_started_at,
       d.last_ended_at,
       d.is_active,
       coalesce(r.status,
                case when d.is_active then 'in_progress' else 'absent' end) as status,
       r.method,
       r.marked_at,
       r.edited_by,
       r.edited_at,
       r.edit_reason,
       -- "Marked by teacher": a manual row or an edited row
       coalesce(r.method = 'manual' or r.edited_at is not null, false) as marked_by_teacher
from course_days d
join public.enrollments e on e.course_id = d.course_id
left join day_rows r
       on r.student_id = e.student_id
      and r.course_id  = d.course_id
      and r.class_date = d.class_date;

revoke all on public.student_daily_attendance from anon;
grant select on public.student_daily_attendance to authenticated;


-- ---------------------------------------------------------------------
-- 3. attendance_summary: same columns as before, now day-based
--    (total_sessions = counted class days, present_count = attended days)
-- ---------------------------------------------------------------------
create or replace view public.attendance_summary
with (security_invoker = true) as
select e.student_id,
       p.full_name,
       p.email,
       e.course_id,
       c.code as course_code,
       c.name as course_name,
       count(d.class_date) filter (where d.status in ('present', 'late', 'absent')) as total_sessions,
       count(d.class_date) filter (where d.status in ('present', 'late'))           as present_count,
       case
         when count(d.class_date) filter (where d.status in ('present', 'late', 'absent')) = 0
           then 100::numeric
         else round(100.0
                    * count(d.class_date) filter (where d.status in ('present', 'late'))
                    / count(d.class_date) filter (where d.status in ('present', 'late', 'absent')), 1)
       end as percentage
from public.enrollments e
join public.profiles p on p.id = e.student_id
join public.courses  c on c.id = e.course_id
left join public.student_daily_attendance d
       on d.student_id = e.student_id and d.course_id = e.course_id
group by e.student_id, p.full_name, p.email, e.course_id, c.code, c.name;

revoke all on public.attendance_summary from anon;
grant select on public.attendance_summary to authenticated;


-- ---------------------------------------------------------------------
-- 4. Student functions
-- ---------------------------------------------------------------------
-- My Attendance (same result columns as before)
create or replace function public.get_my_attendance_summary()
returns table (
  course_id uuid, course_name text, course_code text,
  total_sessions integer, attended_sessions integer
)
language sql stable security definer set search_path = public
as $$
  select c.id, c.name::text, c.code::text,
         (count(d.class_date) filter (where d.status in ('present', 'late', 'absent')))::integer,
         (count(d.class_date) filter (where d.status in ('present', 'late')))::integer
  from enrollments e
  join courses c on c.id = e.course_id
  left join student_daily_attendance d
         on d.student_id = e.student_id and d.course_id = e.course_id
  where e.student_id = auth.uid()
  group by c.id, c.name, c.code
  order by c.code;
$$;

-- History (same result columns as before, ONE row per day)
create or replace function public.get_my_course_history(p_course_id uuid)
returns table (
  session_id uuid, started_at timestamptz, ended_at timestamptz,
  is_active boolean, present boolean, method text, marked_at timestamptz
)
language sql stable security definer set search_path = public
as $$
  select d.first_session_id, d.first_started_at, d.last_ended_at, d.is_active,
         d.status in ('present', 'late'), d.method, d.marked_at
  from student_daily_attendance d
  where d.student_id = auth.uid() and d.course_id = p_course_id
  order by d.class_date desc;
$$;

-- NEW: date-wise list for one course, with the 4 statuses
create or replace function public.get_my_course_days(p_course_id uuid)
returns table (
  class_date date, status text, method text,
  marked_by_teacher boolean, marked_at timestamptz, is_active boolean
)
language sql stable security definer set search_path = public
as $$
  select d.class_date, d.status, d.method, d.marked_by_teacher,
         d.marked_at, d.is_active
  from student_daily_attendance d
  where d.student_id = auth.uid() and d.course_id = p_course_id
  order by d.class_date desc;
$$;


-- ---------------------------------------------------------------------
-- 5. Teacher functions (the course's teacher or an admin only)
-- ---------------------------------------------------------------------
-- All class dates of a course, newest first, with the day's counts.
create or replace function public.get_course_class_days(p_course_id uuid)
returns table (
  class_date date, session_id uuid, is_active boolean,
  attended_count integer,   -- present + late
  counted_count integer,    -- present + late + absent
  enrolled_count integer
)
language sql stable security definer set search_path = public
as $$
  select d.class_date,
         min(d.first_session_id::text)::uuid,
         bool_or(d.is_active),
         (count(*) filter (where d.status in ('present', 'late')))::integer,
         (count(*) filter (where d.status in ('present', 'late', 'absent')))::integer,
         count(*)::integer
  from student_daily_attendance d
  where d.course_id = p_course_id
    and (public.my_role() = 'admin' or public.teaches_course(p_course_id))
  group by d.class_date
  order by d.class_date desc;
$$;

-- Every enrolled student's status on one class day.
create or replace function public.get_course_day_records(p_course_id uuid, p_class_date date)
returns table (
  student_id uuid, full_name text, email text,
  status text, method text, marked_at timestamptz,
  edited_by_name text, edited_at timestamptz, edit_reason text,
  session_id uuid
)
language sql stable security definer set search_path = public
as $$
  select d.student_id,
         coalesce(p.full_name, '')::text,
         coalesce(p.email, '')::text,
         d.status, d.method, d.marked_at,
         ed.full_name::text, d.edited_at, d.edit_reason,
         d.first_session_id
  from student_daily_attendance d
  join profiles p       on p.id = d.student_id
  left join profiles ed on ed.id = d.edited_by
  where d.course_id  = p_course_id
    and d.class_date = p_class_date
    and (public.my_role() = 'admin' or public.teaches_course(p_course_id))
  order by p.full_name;
$$;

-- Change one student's status for one class day.
--   p_session_id : any session of that course and day
--   p_status     : 'present' | 'late' | 'absent' | 'excused'
-- If the student already has a row that day -> UPDATE it (never delete).
-- If not -> add a manual row (no device_id); "absent" needs no row.
-- Always records who edited, when, and the optional reason.
create or replace function public.edit_attendance(
  p_session_id uuid, p_student_id uuid, p_status text, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_course uuid;
  v_day    date;
  v_row    uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  end if;
  if p_status not in ('present', 'late', 'absent', 'excused') then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATUS');
  end if;

  select course_id, (started_at at time zone 'Asia/Karachi')::date
    into v_course, v_day
  from sessions where id = p_session_id;
  if v_course is null then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  end if;

  -- Only this course's teacher or an admin (never a student)
  if not (public.my_role() = 'admin' or public.teaches_course(v_course)) then
    return jsonb_build_object('ok', false, 'code', 'NOT_ALLOWED');
  end if;

  if not exists (select 1 from enrollments
                 where course_id = v_course and student_id = p_student_id) then
    return jsonb_build_object('ok', false, 'code', 'NOT_ENROLLED');
  end if;

  -- The student's row for this course and day (any session of that day)
  select a.id into v_row
  from attendance a
  join sessions s on s.id = a.session_id
  where a.student_id = p_student_id
    and s.course_id = v_course
    and (s.started_at at time zone 'Asia/Karachi')::date = v_day
  order by case a.status when 'present' then 1 when 'late' then 2
                         when 'excused' then 3 else 4 end,
           a.marked_at
  limit 1;

  if v_row is not null then
    update attendance
       set status      = p_status,
           edited_by   = auth.uid(),
           edited_at   = now(),
           edit_reason = v_reason
     where id = v_row;
    return jsonb_build_object('ok', true, 'code', 'UPDATED');
  end if;

  -- No row yet: "absent" is already the default, nothing to store
  if p_status = 'absent' then
    return jsonb_build_object('ok', true, 'code', 'NO_CHANGE');
  end if;

  insert into attendance (session_id, student_id, course_id, device_id, method,
                          status, edited_by, edited_at, edit_reason)
  values (p_session_id, p_student_id, v_course, null, 'manual',
          p_status, auth.uid(), now(), v_reason);
  return jsonb_build_object('ok', true, 'code', 'CREATED');
end;
$$;

-- Rights: logged-in users only (each function checks the role itself)
revoke execute on function public.get_my_attendance_summary()                     from public, anon;
revoke execute on function public.get_my_course_history(uuid)                     from public, anon;
revoke execute on function public.get_my_course_days(uuid)                        from public, anon;
revoke execute on function public.get_course_class_days(uuid)                     from public, anon;
revoke execute on function public.get_course_day_records(uuid, date)              from public, anon;
revoke execute on function public.edit_attendance(uuid, uuid, text, text)         from public, anon;
grant  execute on function public.get_my_attendance_summary()                     to authenticated;
grant  execute on function public.get_my_course_history(uuid)                     to authenticated;
grant  execute on function public.get_my_course_days(uuid)                        to authenticated;
grant  execute on function public.get_course_class_days(uuid)                     to authenticated;
grant  execute on function public.get_course_day_records(uuid, date)              to authenticated;
grant  execute on function public.edit_attendance(uuid, uuid, text, text)         to authenticated;

commit;

notify pgrst, 'reload schema';
