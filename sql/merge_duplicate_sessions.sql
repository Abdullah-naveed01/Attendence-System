-- =====================================================================
-- ONE-TIME CLEANUP: merge duplicate sessions (same course, same day)
--
-- During testing, End Class + Start Class created several sessions for
-- one course on one day. For every course + day (Asia/Karachi date) that
-- has more than one session, this script:
--   1. keeps the EARLIEST session of that day
--   2. keeps ONE attendance row per student for that day: the row already
--      in the earliest session if there is one, otherwise the QR mark,
--      otherwise the first mark; the other (duplicate) rows are removed
--   3. moves the kept rows into the earliest session
--   4. moves audit_logs.session_id to the earliest session (alerts stay
--      linked to the class)
--   5. if one of the day's sessions is still running, the earliest one
--      becomes the running session
--   6. deletes the extra, now empty, sessions
--
-- ONE transaction: if any check fails, NOTHING is changed.
-- Run AFTER sql/session_resume_same_day.sql, so it cannot happen again.
--
-- PART 0 below is a read-only preview you can run first.
-- =====================================================================


-- =====================================================================
-- PART 0 - READ-ONLY PREVIEW (changes nothing)
-- =====================================================================
with day_sessions as (
  select s.id, s.course_id, s.started_at, s.is_active,
         (s.started_at at time zone 'Asia/Karachi')::date as pk_day
  from sessions s
),
groups as (
  select course_id, pk_day, count(*) as sessions,
         (array_agg(id order by started_at))[1] as keep_id
  from day_sessions group by course_id, pk_day having count(*) > 1
)
select c.code, g.pk_day, g.sessions,
       g.sessions - 1 as sessions_to_delete,
       (select count(*) from attendance a join day_sessions d on d.id = a.session_id
         where d.course_id = g.course_id and d.pk_day = g.pk_day
           and a.session_id <> g.keep_id) as rows_to_move_or_drop,
       (select count(*) - count(distinct a.student_id)
          from attendance a join day_sessions d on d.id = a.session_id
         where d.course_id = g.course_id and d.pk_day = g.pk_day) as duplicate_rows_dropped,
       (select count(*) from audit_logs l join day_sessions d on d.id = l.session_id
         where d.course_id = g.course_id and d.pk_day = g.pk_day
           and l.session_id <> g.keep_id) as alerts_relinked
from groups g join courses c on c.id = g.course_id
order by g.pk_day, c.code;


-- =====================================================================
-- PART 1 - THE MERGE (run only after approval)
-- =====================================================================
begin;

do $$
declare
  g      record;
  keep   uuid;
  extras uuid[];
  active boolean;
begin
  for g in
    select course_id,
           (started_at at time zone 'Asia/Karachi')::date as pk_day,
           array_agg(id order by started_at) as ids,
           bool_or(is_active) as any_active,
           max(ended_at) as last_end
    from sessions
    group by course_id, (started_at at time zone 'Asia/Karachi')::date
    having count(*) > 1
  loop
    keep   := g.ids[1];
    extras := g.ids[2:array_length(g.ids, 1)];
    active := g.any_active;

    -- 2. One row per student for the day (keep the earliest session's
    --    row, then a QR mark, then the first mark); drop the others.
    delete from attendance
    where id in (
      select id from (
        select a.id,
               row_number() over (
                 partition by a.student_id
                 order by (a.session_id = keep) desc,
                          (a.method = 'qr') desc,
                          a.marked_at) as rn
        from attendance a
        where a.session_id = any(g.ids)
      ) ranked
      where rn > 1
    );

    -- Safety: one phone may be used by only one student per session.
    if exists (select 1 from attendance
               where session_id = any(g.ids) and device_id is not null
               group by device_id having count(distinct student_id) > 1) then
      raise exception 'Course % on %: two students used the same phone. Nothing was changed.',
        g.course_id, g.pk_day;
    end if;

    -- 3. Move the kept rows into the earliest session
    update attendance set session_id = keep where session_id = any(extras);

    -- 4. Alerts stay linked to the class
    update audit_logs set session_id = keep where session_id = any(extras);

    -- 5. Running state: only one session per course may be active
    update sessions set is_active = false where id = any(extras);
    update sessions
       set is_active = active,
           ended_at  = case when active then null else g.last_end end
     where id = keep;

    -- 6. Delete the extra (now empty) sessions
    if exists (select 1 from attendance where session_id = any(extras)) then
      raise exception 'An extra session still has attendance. Nothing was changed.';
    end if;
    delete from sessions where id = any(extras);
  end loop;
end $$;

commit;

-- CHECK (read-only): no course has more than one session on a day.
-- Expected: 0 rows
select c.code, (s.started_at at time zone 'Asia/Karachi')::date as pk_day, count(*) as sessions
from sessions s join courses c on c.id = s.course_id
group by c.code, (s.started_at at time zone 'Asia/Karachi')::date
having count(*) > 1;
