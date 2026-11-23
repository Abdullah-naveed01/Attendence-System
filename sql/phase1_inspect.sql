-- =====================================================================
-- PHASE 1 - READ-ONLY inspection. Changes nothing.
-- Lists: server function code, indexes, columns, RLS policies,
-- triggers, and which tables have Realtime enabled.
--
-- Run in the Supabase SQL Editor, then: Export -> Download CSV,
-- and save the file as  sql/phase1_inspect_result.csv  in the project.
-- =====================================================================

select 'function' as kind,
       p.proname as name,
       pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('start_session', 'start_session_core', 'mark_attendance',
                    'refresh_qr_token', 'end_session', 'reset_device')

union all
select 'index', tablename || '.' || indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('sessions', 'attendance', 'profiles', 'audit_logs',
                    'courses', 'enrollments', 'timetable')

union all
select 'column', table_name || '.' || column_name,
       data_type
         || case when is_nullable = 'NO' then ' NOT NULL' else '' end
         || coalesce(' DEFAULT ' || column_default, '')
from information_schema.columns
where table_schema = 'public'
  and table_name in ('sessions', 'attendance', 'audit_logs', 'profiles',
                     'courses', 'enrollments', 'timetable')

union all
select 'constraint', conrelid::regclass::text || '.' || conname,
       pg_get_constraintdef(oid)
from pg_constraint
where connamespace = 'public'::regnamespace
  and contype in ('c', 'f', 'u', 'p')

union all
select 'policy', tablename || '.' || policyname,
       cmd || ' to ' || array_to_string(roles, ',')
         || ' USING ' || coalesce(qual, '-')
         || ' CHECK ' || coalesce(with_check, '-')
from pg_policies
where schemaname = 'public'

union all
select 'trigger', event_object_table || '.' || trigger_name, action_statement
from information_schema.triggers
where trigger_schema = 'public'

union all
select 'realtime', tablename, 'in supabase_realtime publication'
from pg_publication_tables
where pubname = 'supabase_realtime'

order by 1, 2;
