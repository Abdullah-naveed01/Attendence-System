-- =====================================================================
-- Shows the student WHICH class their attendance was just marked for:
-- course code, course name, teacher name and the time it was marked.
--
-- Read-only: it only SELECTs. It does not change mark_attendance or any data.
-- It uses auth.uid(), so a student only ever sees their OWN latest record.
-- "security definer" is needed because students may not read the
-- teacher's profile (name) directly under RLS.
-- =====================================================================

create or replace function public.get_my_last_attendance()
returns table (
  course_code  text,
  course_name  text,
  teacher_name text,
  marked_at    timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select c.code::text,
         c.name::text,
         coalesce(t.full_name, '')::text,
         a.marked_at::timestamptz
  from attendance a
  join courses c on c.id = a.course_id
  left join profiles t on t.id = c.teacher_id
  where a.student_id = auth.uid()
  order by a.marked_at desc
  limit 1;
$$;

-- Only logged-in users may call it.
revoke execute on function public.get_my_last_attendance() from public, anon;
grant execute on function public.get_my_last_attendance() to authenticated;

notify pgrst, 'reload schema';
