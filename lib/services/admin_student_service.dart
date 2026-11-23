import '../core/admin_function.dart';
import '../core/supabase_client.dart';
import '../models/course.dart';
import '../models/profile.dart';
import '../models/student_summary.dart';

// Admin-only student management.
//
// Reading is a normal query (RLS lets an admin read everything).
// Adding, enrolling and deleting go through the admin Edge Function,
// which checks that the caller is an admin.
//
// All students are in the same class: a student takes every course that
// appears in the timetable ("class courses").
class AdminStudentService {
  // Every student with the number of courses they are enrolled in.
  Future<List<StudentSummary>> getStudents() async {
    final profileRows = await supabase
        .from('profiles')
        .select()
        .eq('role', 'student')
        .order('full_name');
    final enrollmentRows =
        await supabase.from('enrollments').select('student_id');

    // Count enrollments per student
    final counts = <String, int>{};
    for (final row in enrollmentRows) {
      final id = row['student_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }

    return profileRows.map((row) {
      final profile = Profile.fromMap(row);
      return StudentSummary(
          profile: profile, courseCount: counts[profile.id] ?? 0);
    }).toList();
  }

  // The class courses: every course with a timetable slot, sorted by code.
  Future<List<Course>> getClassCourses() async {
    final rows = await supabase.from('timetable').select('courses(*)');

    final byId = <String, Course>{};
    for (final row in rows) {
      final course = row['courses'];
      if (course != null) {
        final c = Course.fromMap(Map<String, dynamic>.from(course));
        byId[c.id] = c;
      }
    }
    final courses = byId.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    return courses;
  }

  // How many attendance records a student has (shown before deleting).
  Future<int> countAttendance(String studentId) async {
    final rows = await supabase
        .from('attendance')
        .select('id')
        .eq('student_id', studentId);
    return rows.length;
  }

  // Creates the login account + student profile + class enrollments.
  // Returns how many courses the student was enrolled in.
  Future<int> addStudent({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final data = await callAdminFunction({
      'action': 'add_student',
      'full_name': fullName.trim(),
      'email': email.trim(),
      'password': password,
    });
    return (data['courses_enrolled'] as num?)?.toInt() ?? 0;
  }

  // Adds the class courses the student is missing. Returns how many.
  Future<int> enrollInAllClassCourses(String studentId) async {
    final data = await callAdminFunction(
        {'action': 'enroll_all', 'student_id': studentId});
    return (data['courses_enrolled'] as num?)?.toInt() ?? 0;
  }

  // Permanently deletes the student. Returns how many attendance
  // records were deleted.
  Future<int> deleteStudent(String studentId) async {
    final data = await callAdminFunction(
        {'action': 'delete_student', 'student_id': studentId});
    return (data['attendance_deleted'] as num?)?.toInt() ?? 0;
  }
}
