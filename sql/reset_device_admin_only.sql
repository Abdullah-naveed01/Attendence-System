-- =====================================================================
-- Only an ADMIN can reset a student's device (phone binding).
--
-- Before: admin OR a teacher of the student (teaches_student) could reset.
-- After : admin only. Everyone else gets {ok:false, code:'NOT_ALLOWED'}.
--
-- Everything else is unchanged: device_id is cleared and a DEVICE_RESET
-- row is written to audit_logs, and the answer is the same JSON.
-- The admin resets phones from the "Student Devices" screen; teachers
-- are told to contact the admin.
-- =====================================================================

create or replace function public.reset_device(p_student_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Admin only (teachers are no longer allowed)
  if public.my_role() is distinct from 'admin' then
    return jsonb_build_object('ok', false, 'code', 'NOT_ALLOWED');
  end if;

  update public.profiles set device_id = null where id = p_student_id;
  perform public.log_event('DEVICE_RESET', 'low', null, null, p_student_id, auth.uid(), null,
                           jsonb_build_object('reset_by', auth.uid()));
  return jsonb_build_object('ok', true, 'code', 'DEVICE_RESET');
end;
$$;

-- Same rights as before (the function checks the role itself)
revoke execute on function public.reset_device(uuid) from public, anon;
grant  execute on function public.reset_device(uuid) to authenticated;

notify pgrst, 'reload schema';

-- CHECK (read-only): teaches_student is no longer in the function.
-- Expected: admin_only = true
select pg_get_functiondef('public.reset_device(uuid)'::regprocedure)
         not like '%teaches_student%' as admin_only;
