-- =====================================================================
-- Proxy alerts go ONLY to the teacher of the course where the attempt
-- happened. Admin and other teachers can NOT read alerts any more.
--
-- What this does (one transaction - all or nothing):
--   1. Shows nothing and stops if audit_logs has a "FOR ALL" policy
--      (we would not know if writing depends on it) -> nothing changed.
--   2. Removes every existing SELECT and UPDATE policy on audit_logs
--      (the old ones also let the admin read alerts).
--   3. Adds two new policies:
--        read   : only the teacher of the alert's course
--        update : only the teacher of the alert's course (mark as read)
--   4. Makes sure the app can change ONLY the is_read column.
--
-- INSERT is not touched: alerts are written only by the server
-- functions (mark_attendance, reset_device), never by the app.
-- Realtime follows the read policy, so the live popup also reaches
-- only the course's teacher.
-- =====================================================================

begin;

do $$
declare
  p record;
begin
  -- 1. Safety stop: a FOR ALL policy could be needed for writing
  if exists (select 1 from pg_policies
             where schemaname = 'public' and tablename = 'audit_logs'
               and cmd = 'ALL') then
    raise exception 'audit_logs has a FOR ALL policy. Nothing was changed. Send this message to Claude.';
  end if;

  -- 2. Remove the old read / update policies
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'audit_logs'
      and cmd in ('SELECT', 'UPDATE')
  loop
    execute format('drop policy %I on public.audit_logs', p.policyname);
  end loop;
end $$;

-- 3a. Read: only the teacher of the alert's course
create policy "audit_logs_course_teacher_read" on public.audit_logs
  for select to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = audit_logs.course_id
                   and c.teacher_id = auth.uid()));

-- 3b. Mark as read: only the teacher of the alert's course
create policy "audit_logs_course_teacher_update" on public.audit_logs
  for update to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = audit_logs.course_id
                   and c.teacher_id = auth.uid()))
  with check (exists (select 1 from public.courses c
                      where c.id = audit_logs.course_id
                        and c.teacher_id = auth.uid()));

-- 4. The app may change only is_read (not the event, names or severity)
revoke update on public.audit_logs from authenticated;
grant update (is_read) on public.audit_logs to authenticated;

commit;

-- =====================================================================
-- CHECK (read-only): the policies now on audit_logs.
-- Expected: the two new policies above (+ any INSERT policy, untouched).
-- =====================================================================
select policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public' and tablename = 'audit_logs'
order by cmd, policyname;
