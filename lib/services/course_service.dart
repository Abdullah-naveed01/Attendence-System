import '../core/supabase_client.dart';
import '../models/course.dart';

// Database queries related to courses.
class CourseService {
  // The courses taught by this teacher, sorted by course code.
  Future<List<Course>> getTeacherCourses(String teacherId) async {
    final rows = await supabase
        .from('courses')
        .select()
        .eq('teacher_id', teacherId)
        .order('code');

    return rows.map((row) => Course.fromMap(row)).toList();
  }

  // The courses this student is enrolled in, sorted by course code.
  // We read the student's enrollments and ask Supabase to include
  // the linked course row for each one: courses(*).
  Future<List<Course>> getStudentCourses(String studentId) async {
    final rows = await supabase
        .from('enrollments')
        .select('courses(*)')
        .eq('student_id', studentId);

    final courses = <Course>[];
    for (final row in rows) {
      final course = row['courses'];
      // course is null if RLS does not let the student read that course
      if (course != null) {
        courses.add(Course.fromMap(Map<String, dynamic>.from(course)));
      }
    }
    courses.sort((a, b) => a.code.compareTo(b.code));
    return courses;
  }
}
