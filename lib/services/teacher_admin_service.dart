import '../core/admin_function.dart';
import '../core/supabase_client.dart';
import '../models/course.dart';
import '../models/profile.dart';
import '../models/teacher_summary.dart';

// Admin-only teacher management.
//
// Reading (teachers, courses) is a normal query: RLS lets an admin read all.
// Creating and deleting login accounts needs the service_role key, so the app
// asks the admin Edge Function to do it on the server
// (see lib/core/admin_function.dart).
class TeacherAdminService {
  // Every course, sorted by code.
  Future<List<Course>> getAllCourses() async {
    final rows = await supabase.from('courses').select().order('code');
    return rows.map((row) => Course.fromMap(row)).toList();
  }

  // Every teacher with the courses they own.
  Future<List<TeacherSummary>> getTeachers(List<Course> allCourses) async {
    final rows = await supabase
        .from('profiles')
        .select()
        .eq('role', 'teacher')
        .order('full_name');

    return rows.map((row) {
      final profile = Profile.fromMap(row);
      return TeacherSummary(
        profile: profile,
        courses: allCourses.where((c) => c.teacherId == profile.id).toList(),
      );
    }).toList();
  }

  Future<void> createTeacher({
    required String fullName,
    required String email,
    required String password,
    required List<String> existingCourseIds,
    required List<NewCourseInput> newCourses,
  }) async {
    await callAdminFunction({
      'action': 'create',
      'full_name': fullName.trim(),
      'email': email.trim(),
      'password': password,
      'courses': [
        for (final id in existingCourseIds) {'course_id': id},
        for (final course in newCourses) {'new_course': course.toJson()},
      ],
    });
  }

  Future<void> removeTeacher(String teacherId) async {
    await callAdminFunction({'action': 'remove', 'teacher_id': teacherId});
  }
}
