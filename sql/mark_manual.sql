-- =====================================================================
-- FR-23: Manual attendance  ->  mark_manual(p_session_id, p_student_id)
--
-- Why a function and not a direct INSERT from the app:
-- app users have no INSERT right on attendance (only SELECT), so all
-- attendance is written by server functions, like mark_attendance.
-- This keeps every check on the server.
--
-- Checks, in order:
--   not logged in                         -> NOT_AUTHENTICATED
--   session missing or already ended      -> SESSION_NOT_ACTIVE
--   caller is not admin / course teacher  -> NOT_ALLOWED
--   student not enrolled in this course   -> NOT_ENROLLED
--   student already marked in the session -> ALREADY_MARKED
--   otherwise insert the row              -> MARKED
--
-- The row: method = 'manual', device_id = NULL (no phone was used),
-- status = 'present' (the column default).
-- =====================================================================

create or replace function public.mark_manual(p_session_id uuid, p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_course uuid;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  end if;

  -- Only a running class
  select course_id into v_course
  from public.sessions
  where id = p_session_id and is_active;
  if v_course is null then
    return jsonb_build_object('ok', false, 'code', 'SESSION_NOT_ACTIVE');
  end if;

  -- Only the admin or this course's teacher
  if not (public.my_role() = 'admin' or public.teaches_course(v_course)) then
    return jsonb_build_object('ok', false, 'code', 'NOT_ALLOWED');
  end if;

  -- Only students enrolled in this course
  if not exists (select 1 from public.enrollments
                 where course_id = v_course and student_id = p_student_id) then
    return jsonb_build_object('ok', false, 'code', 'NOT_ENROLLED');
  end if;

  begin
    insert into public.attendance (session_id, student_id, course_id, device_id, method)
    values (p_session_id, p_student_id, v_course, null, 'manual');
  exception when unique_violation then
    -- UNIQUE(session_id, student_id): already marked (by QR or manually)
    return jsonb_build_object('ok', false, 'code', 'ALREADY_MARKED');
  end;

  return jsonb_build_object('ok', true, 'code', 'MARKED');
end;
$$;

-- Only logged-in users may call it (the function checks the role itself).
revoke execute on function public.mark_manual(uuid, uuid) from public, anon;
grant  execute on function public.mark_manual(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
