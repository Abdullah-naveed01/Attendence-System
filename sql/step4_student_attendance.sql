-- Step 4: student attendance records
-- Run this whole file once in the Supabase SQL Editor.
-- It only ADDS two read-only functions. It does not change any table or data.
--
-- Both functions use auth.uid(), so a student can only ever see THEIR OWN data.
-- "security definer" lets the function read sessions/attendance even if RLS
-- would not let the student read the sessions table directly.
--
-- Counting rule:
--   A class (session) counts toward the total once it has ENDED.
--   A class that is still running is not counted yet, unless the student has
--   already scanned it (then it counts as attended).

-- 1) Percentage per course: total classes and attended classes
create or replace function public.get_my_attendance_summary()
returns table (
  course_id uuid,
  course_name text,
  course_code text,
  total_sessions integer,
  attended_sessions integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.name::text,
    c.code::text,
    (count(s.id) filter (where s.is_active = false or a.id is not null))::integer,
    count(a.id)::integer
  from enrollments e
  join courses c on c.id = e.course_id
  left join sessions s on s.course_id = c.id
  left join attendance a on a.session_id = s.id and a.student_id = e.student_id
  where e.student_id = auth.uid()
  group by c.id, c.name, c.code
  order by c.code;
$$;

-- 2) Session-by-session history for one course (newest first)
create or replace function public.get_my_course_history(p_course_id uuid)
returns table (
  session_id uuid,
  started_at timestamptz,
  ended_at timestamptz,
  is_active boolean,
  present boolean,
  method text,
  marked_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id,
    s.started_at::timestamptz,
    s.ended_at::timestamptz,
    s.is_active,
    (a.id is not null),
    a.method::text,
    a.marked_at::timestamptz
  from sessions s
  -- only courses the student is enrolled in
  join enrollments e on e.course_id = s.course_id and e.student_id = auth.uid()
  left join attendance a on a.session_id = s.id and a.student_id = auth.uid()
  where s.course_id = p_course_id
  order by s.started_at desc;
$$;

-- Only logged-in users may call these functions (not anonymous visitors).
revoke execute on function public.get_my_attendance_summary() from public, anon;
revoke execute on function public.get_my_course_history(uuid) from public, anon;
grant execute on function public.get_my_attendance_summary() to authenticated;
grant execute on function public.get_my_course_history(uuid) to authenticated;

-- Make the API see the new functions immediately.
notify pgrst, 'reload schema';
