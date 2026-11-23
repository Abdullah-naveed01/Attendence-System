-- =====================================================================
-- Admin teacher management: database preparation
-- Run in the Supabase SQL Editor BEFORE using "Remove Teacher".
-- =====================================================================

-- 1) A course may have no teacher.
--    When a teacher is removed, their courses are kept (with all sessions
--    and attendance) and only teacher_id is set to NULL.
--    If teacher_id already allows NULL, this does nothing.
alter table public.courses alter column teacher_id drop not null;

-- 2) READ-ONLY CHECK: course codes must be unique, and this lists every
--    table that points to profiles (so we know deleting a teacher's
--    profile is safe). Send Claude the result if anything looks unclear.
select conrelid::regclass        as "table",
       conname                   as "rule",
       pg_get_constraintdef(oid) as definition
from pg_constraint
where (contype = 'u' and conrelid = 'public.courses'::regclass)
   or (contype = 'f' and (confrelid = 'public.profiles'::regclass
                          or conrelid = 'public.profiles'::regclass))
order by 1, 2;
