# Smart Attendance System (Flutter + Supabase)

## Project
Semester project (App Development), 1 month, beginner developer.
Android-only Flutter app. QR attendance with device binding and audit log.
Explain things simply, in professional English only (no Roman Urdu) —
in replies, app UI text, and code comments.

## Fixed decisions (do not change)
- Flutter (Dart), Android only. No web/iOS/desktop work.
- Backend is Supabase ONLY (Auth + PostgreSQL + RLS + RPC + Realtime).
  No Node/Express/MongoDB/Firebase.
- Only the anon key in the app. NEVER the service_role key.
- All attendance verification happens on the server (RPC), never in the app.
- One app, 3 roles from profiles.role: admin, teacher, student.

## Backend status: ALREADY DONE in Supabase
Do NOT recreate or change the database without asking me first.

Supabase URL: https://roqofpqikwjhrdviicio.supabase.co
(anon key goes in lib/main.dart, I add it myself)

Tables:
- profiles(id, full_name, email, role 'admin'|'teacher'|'student', device_id unique)
- courses(id, name, code, semester, teacher_id)
- enrollments(id, student_id, course_id)  UNIQUE(student_id, course_id)
- sessions(id, course_id, started_at, ended_at, is_active, qr_token,
  qr_expires_at, qr_prev_token, qr_prev_expires_at)
- attendance(id, session_id, student_id, course_id, device_id,
  method 'qr'|'manual', marked_at,
  status 'present'|'late'|'absent'|'excused', edited_by, edited_at, edit_reason)
  UNIQUE(session_id, student_id): ONE row per student per session.
  Partial unique index attendance_one_present_per_device ON (session_id,
  device_id) WHERE status IN ('present','late'): one phone can be PRESENT
  for only one student per session. Absent/excused rows keep their
  device_id (evidence) but do not block the phone. (Replaced the old
  UNIQUE(session_id, device_id); sql/proxy_absent_device_fix.sql.)
  Latest action wins: teacher sets absent -> row kept as 'absent'; a later
  valid scan updates the SAME row to 'present'; never a second row.
- audit_logs(id, event_type, severity 'low'|'high', session_id, course_id,
  account_id, device_owner_id, device_id, details, is_read, created_at)

- timetable(id, course_id, day_of_week 1=Mon..7=Sun, start_time, end_time)
  UNIQUE(course_id, day_of_week, start_time). Times are Pakistan time.
  Created/filled by sql/teachers_timetable_lock.sql (user runs it).
  Read: admin / course teacher / enrolled student. Write: admin.
  Each lab is its own course (own Start Class + own attendance):
  CS-301/CS-301L ashfaq@test.com, CS-303/CS-303L riaz@test.com,
  CS-304 shahid@test.com, CS-304L adil@test.com, CS-305 sarah@test.com,
  CS-306 maira@test.com, CS-307/CS-307L areeba@test.com (passwords Test@1234).
  teacher@test.com keeps CS-302 (not on timetable).
  Labs split by sql/split_labs.sql.

Edge Function manage-teacher (supabase/functions/manage-teacher/index.ts):
admin-only (uses service_role on the server only). Actions: create / remove
teacher, add_student, enroll_all, delete_student.
Deployed in Supabase under the name "rapid-task" (dashboard random name).
App calls it through lib/core/admin_function.dart (callAdminFunction).
Needs sql/admin_teachers.sql (courses.teacher_id nullable) and
sql/admin_students.sql (admin_delete_student, callable only by service_role).
Removing a teacher unassigns courses, keeps attendance.
All students are in one class: add_student / enroll_all enroll a student in
every course that has a timetable slot ("class courses").

Attendance is never deleted, with ONE exception: permanently deleting a
student (admin, delete_student) deletes that student's attendance,
enrollments, profile and login account in one transaction. audit_logs rows
are kept (account columns become NULL via ON DELETE SET NULL).

Time lock: start_session is a wrapper that returns {ok:false, code:'NOT_SCHEDULED'}
unless Asia/Karachi time is inside a timetable slot (start_time <= now < end_time);
admin always allowed. The original function was renamed to start_session_core
(unchanged, not callable by the app). App mirrors the rule with pakistanNow()
(UTC+5) in lib/core/pakistan_time.dart.

One session per course per day (Asia/Karachi date), never into another day
(sql/session_one_day_only.sql):
- start_session first calls end_old_sessions(course): an ACTIVE session from
  an earlier day is ended (ended_at = its slot end, or the last second of
  that day if it had no slot). Then: same day -> today's session is resumed
  (resumed = true, attendance kept); new day -> a NEW session (empty).
- mark_attendance accepts only a QR whose session started TODAY (else
  INVALID_QR).
- pg_cron job "end-active-sessions-daily" runs at 23:59 Pakistan time
  (cron '59 18 * * *', pg_cron uses UTC) and calls
  end_old_sessions(null, true) to end every session still active.
- end_old_sessions(p_course_id, p_include_today) is internal: anon /
  authenticated cannot execute it.

RLS: student sees own data; teacher sees own courses; admin sees all.
Profiles: teacher/admin can read all profiles. Only admin can update profiles.
Realtime is enabled on attendance and audit_logs.

Proxy alerts rule: an alert (audit_logs row) goes ONLY to the teacher of
the course where the attempt happened. The admin and other teachers never
see it (no list, no badge, no realtime popup). Enforced by RLS
(policies audit_logs_course_teacher_read / _update, applied by
sql/proxy_absent_device_fix.sql Part A: select/update only for
courses.teacher_id = auth.uid(); the app may update only is_read) and again
in lib/services/alert_service.dart (every query filters courses.teacher_id).
The banner (lib/widgets/alerts_button.dart) exists only on Teacher Home and
shows only while the same teacher is logged in; auth_gate.dart clears open
banners on logout / login.
Alerts are written only by server functions. The admin resets phones from
the admin Students screen, not from alerts.
A trigger creates a profiles row (role 'student') on every signup.

RPC functions (call with supabase.rpc, all return JSON {ok, code, ...}):
(param names verified from the database)
- start_session(p_course_id uuid) -> {ok, code 'STARTED', session_id, token, expires_at}
  (the QR value is under the key "token", not "qr_token")
- refresh_qr_token(p_session_id uuid) -> {ok, token, ...}   (teacher app calls every 30s)
- mark_attendance(p_token text, p_device_id text) -> codes:
  MARKED, INVALID_QR, NOT_ENROLLED, ALREADY_MARKED, NO_DEVICE_ID,
  NOT_AUTHENTICATED, DEVICE_MULTI_STUDENT / DEVICE_MISMATCH /
  DEVICE_ALREADY_BOUND (all shown as "phone not registered" in the app).
  Row present/late -> ALREADY_MARKED; row absent/excused -> updated to
  present (MARKED); no row -> inserted (MARKED). DEVICE_MULTI_STUDENT only
  counts another student's present/late row with the same phone.
- end_session(p_session_id uuid) -> {ok}
- reset_device(p_student_id uuid) -> {ok}

Device id = Android ID (Settings.Secure.ANDROID_ID), not MAC address.
device_info_plus no longer exposes it, so it is read through a small
MethodChannel "smart_attendance/device" in MainActivity.kt
(lib/services/device_service.dart). device_info_plus is used only for the phone model.
QR content = the qr_token string only.

## Test data
Test users (password Test@1234):
admin@test.com, teacher@test.com, student1@test.com,
student2@test.com, student3@test.com
Courses (teacher = teacher@test.com):
CS-301 Mobile App Development, CS-302 Database Systems
All 3 students are enrolled in both courses.

## Packages already installed
supabase_flutter, device_info_plus, mobile_scanner, qr_flutter, local_auth

## Android setup needed
- AndroidManifest: INTERNET, CAMERA, USE_BIOMETRIC permissions
- MainActivity must extend FlutterFragmentActivity (for local_auth)

## Folder structure (lib/)
main.dart, core/, models/, services/,
screens/{auth,student,teacher,admin}/, widgets/

## Screens to build
- Common: Login, Profile
- Student: Home (my courses), Scan QR (biometric first),
  My Attendance (percentage per course, warning below 75%), History
- Teacher: Home (my courses), Start Session (QR refreshing every 30s,
  End button), Live Attendance List (Realtime), Manual Edit,
  Alerts (audit_logs via Realtime, high severity in red, mark as read),
  Reset Device
- Admin: Dashboard, Courses, Users/Roles, Enrollments, Students
  (no Alerts: proxy alerts are for the course's teacher only)

## How to work with me
- Work in small steps. One feature at a time, then stop and tell me how
  to test it on the Android emulator/phone.
- Explain what each new file does in 2-3 lines.
- Don't add packages without asking.
- Keep code simple and readable (I must defend it in front of my teacher).
