-- =====================================================================
-- ANNOUNCEMENTS module
--
-- Run in the Supabase SQL Editor in TWO parts:
--   PART 1  table + security (RLS) + student read function + Realtime
--   PART 2  daily cleanup job (pg_cron) - run after enabling pg_cron
--
-- Rules:
--   Teacher : post / edit / delete ONLY for courses they teach
--   Student : read ONLY for enrolled courses, and only if not expired
--   Admin   : read all
--   Every announcement expires 7 days after it was posted:
--   hidden from students at once, deleted by the daily job.
-- =====================================================================


-- =====================================================================
-- PART 1
-- =====================================================================
begin;

-- ---------- 1. The table ----------
create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  course_id   uuid not null references public.courses(id) on delete cascade,
  -- if the teacher's account is removed, the announcement stays
  teacher_id  uuid references public.profiles(id) on delete set null,
  title       text not null check (length(trim(title)) between 1 and 120),
  message     text not null check (length(trim(message)) between 1 and 2000),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '7 days'
);

-- Fast "newest first per course"
create index if not exists announcements_course_created_idx
  on public.announcements (course_id, created_at desc);

alter table public.announcements enable row level security;

-- ---------- 2. Who may do what (RLS) ----------
-- READ: the course's teacher, enrolled students (only if not expired), admin
drop policy if exists "announcements_read" on public.announcements;
create policy "announcements_read" on public.announcements
  for select to authenticated
  using (
    exists (select 1 from public.courses c
            where c.id = announcements.course_id and c.teacher_id = auth.uid())
    or (announcements.expires_at > now()
        and exists (select 1 from public.enrollments e
                    where e.course_id = announcements.course_id
                      and e.student_id = auth.uid()))
    or exists (select 1 from public.profiles p
               where p.id = auth.uid() and p.role = 'admin')
  );

-- POST: only for a course you teach, and only in your own name
drop policy if exists "announcements_teacher_insert" on public.announcements;
create policy "announcements_teacher_insert" on public.announcements
  for insert to authenticated
  with check (
    teacher_id = auth.uid()
    and exists (select 1 from public.courses c
                where c.id = announcements.course_id and c.teacher_id = auth.uid())
  );

-- EDIT: only announcements of a course you teach
drop policy if exists "announcements_teacher_update" on public.announcements;
create policy "announcements_teacher_update" on public.announcements
  for update to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = announcements.course_id and c.teacher_id = auth.uid()))
  with check (exists (select 1 from public.courses c
                      where c.id = announcements.course_id and c.teacher_id = auth.uid()));

-- DELETE: only announcements of a course you teach
drop policy if exists "announcements_teacher_delete" on public.announcements;
create policy "announcements_teacher_delete" on public.announcements
  for delete to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = announcements.course_id and c.teacher_id = auth.uid()));

-- Column rights: the app may set only course/teacher/title/message when
-- posting, and change only title/message when editing. created_at and
-- expires_at are always set by the database (no one can extend 7 days).
revoke all on public.announcements from anon;
revoke insert, update on public.announcements from authenticated;
grant select, delete on public.announcements to authenticated;
grant insert (course_id, teacher_id, title, message) on public.announcements to authenticated;
grant update (title, message) on public.announcements to authenticated;

-- ---------- 3. Student list WITH the teacher's name ----------
-- Students may not read teachers' profiles (RLS), so this read-only
-- function adds the teacher's name. It returns only the caller's
-- enrolled courses and only announcements that have not expired.
create or replace function public.get_my_announcements()
returns table (
  id           uuid,
  course_id    uuid,
  course_code  text,
  course_name  text,
  title        text,
  message      text,
  teacher_name text,
  created_at   timestamptz,
  expires_at   timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.course_id, c.code::text, c.name::text,
         a.title, a.message, coalesce(p.full_name, '')::text,
         a.created_at, a.expires_at
  from announcements a
  join enrollments e on e.course_id = a.course_id and e.student_id = auth.uid()
  join courses c     on c.id = a.course_id
  left join profiles p on p.id = a.teacher_id
  where a.expires_at > now()
  order by a.created_at desc;
$$;

revoke execute on function public.get_my_announcements() from public, anon;
grant execute on function public.get_my_announcements() to authenticated;

-- ---------- 4. Realtime (new announcements appear live) ----------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'announcements') then
    alter publication supabase_realtime add table public.announcements;
  end if;
end $$;

commit;

notify pgrst, 'reload schema';


-- =====================================================================
-- PART 2 - daily cleanup (pg_cron)
-- Deletes announcements whose 7 days are over, every day at 03:00
-- Pakistan time (= 22:00 UTC; pg_cron uses UTC).
--
-- If the next line fails with "extension pg_cron is not available" or a
-- permission error: Supabase Dashboard -> Integrations -> Cron ->
-- Enable (or Database -> Extensions -> search "pg_cron" -> Enable),
-- then run PART 2 again.
-- =====================================================================
create extension if not exists pg_cron;

-- Remove an older copy of the job first, so running this twice is safe
select cron.unschedule(jobid)
from cron.job
where jobname = 'delete-expired-announcements';

select cron.schedule(
  'delete-expired-announcements',
  '0 22 * * *',
  $$delete from public.announcements where expires_at < now()$$
);

-- CHECK (read-only): the job is scheduled
select jobname, schedule, command from cron.job
where jobname = 'delete-expired-announcements';
