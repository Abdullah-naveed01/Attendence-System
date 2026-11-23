-- FOR TESTING ONLY: adds a temporary CS-302 class (teacher@test.com) that
-- starts 2 minutes from now (Pakistan time) and lasts 30 minutes.
-- CS-302 is not on the real timetable, so this does not disturb it.

insert into public.timetable (course_id, day_of_week, start_time, end_time)
select c.id,
       extract(isodow from now() at time zone 'Asia/Karachi')::smallint,
       date_trunc('minute', (now() at time zone 'Asia/Karachi') + interval '2 minutes')::time,
       date_trunc('minute', (now() at time zone 'Asia/Karachi') + interval '32 minutes')::time
from public.courses c
where c.code = 'CS-302';

-- When you are done testing, remove the test class:
-- delete from public.timetable t using public.courses c
-- where t.course_id = c.id and c.code = 'CS-302';
