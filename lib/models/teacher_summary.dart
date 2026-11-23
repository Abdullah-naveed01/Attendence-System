import 'course.dart';
import 'profile.dart';

// One row of the admin's Teachers list: the teacher and the courses they own.
class TeacherSummary {
  final Profile profile;
  final List<Course> courses;

  TeacherSummary({required this.profile, required this.courses});

  String get displayName =>
      profile.fullName.isEmpty ? profile.email : profile.fullName;
}

// A course the admin wants to create while adding a teacher.
class NewCourseInput {
  final String name;
  final String code;
  final String semester;

  NewCourseInput({
    required this.name,
    required this.code,
    required this.semester,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'code': code, 'semester': semester};
}
