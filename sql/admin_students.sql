-- =====================================================================
-- Admin student management: permanent "Delete Student".
--
-- Deleting a student is the ONE allowed exception to
-- "attendance is never deleted".
--
-- admin_delete_student() deletes, in ONE transaction (all or nothing):
--   1. the student's attendance rows
--   2. the student's enrollments
--   3. the student's profile
--   4. the student's login account (auth.users)
-- audit_logs rows are KEPT; their account columns become NULL
-- (ON DELETE SET NULL). If any step fails, nothing is deleted.
--
-- Only the Edge Function may call it (service_role). The Edge Function
-- first checks that the caller is an admin. Students, teachers and the
-- app itself can NOT call this function.
-- =====================================================================

create or replace function public.admin_delete_student(p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  student_role text;
  attendance_deleted integer;
begin
  -- Only students can be deleted here (never a teacher or an admin)
  select role into student_role from public.profiles where id = p_student_id;
  if student_role is null then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  end if;
  if student_role <> 'student' then
    return jsonb_build_object('ok', false, 'code', 'NOT_A_STUDENT');
  end if;

  -- 1. attendance (count it, so the app can confirm what was removed)
  delete from public.attendance where student_id = p_student_id;
  get diagnostics attendance_deleted = row_count;

  -- 2. enrollments
  delete from public.enrollments where student_id = p_student_id;

  -- 3. profile (audit_logs.account_id / device_owner_id become NULL)
  delete from public.profiles where id = p_student_id;

  -- 4. login account (Supabase also removes its sessions and identities)
  delete from auth.users where id = p_student_id;

  return jsonb_build_object('ok', true, 'code', 'DELETED',
                            'attendance_deleted', attendance_deleted);
end;
$$;

-- Nobody in the app may call it; only the Edge Function (service_role).
revoke execute on function public.admin_delete_student(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_delete_student(uuid) to service_role;

notify pgrst, 'reload schema';


-- =====================================================================
-- READ-ONLY CHECK: what happens to other tables when a profile is
-- deleted. Expected: audit_logs -> ON DELETE SET NULL.
-- (attendance and enrollments are deleted by the function first.)
-- =====================================================================
select conrelid::regclass as "table",
       conname            as "rule",
       pg_get_constraintdef(oid) as definition
from pg_constraint
where contype = 'f'
  and (confrelid = 'public.profiles'::regclass
       or (conrelid = 'public.profiles'::regclass))
order by 1, 2;
