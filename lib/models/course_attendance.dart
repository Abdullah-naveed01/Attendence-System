// One row of get_my_attendance_summary(): the student's numbers for one course.
class CourseAttendance {
  static const double minimumPercent = 75;

  final String courseId;
  final String courseName;
  final String courseCode;
  final int totalSessions; // classes held (ended) so far
  final int attendedSessions; // classes the student was present in

  CourseAttendance({
    required this.courseId,
    required this.courseName,
    required this.courseCode,
    required this.totalSessions,
    required this.attendedSessions,
  });

  factory CourseAttendance.fromMap(Map<String, dynamic> map) {
    return CourseAttendance(
      courseId: map['course_id'] as String,
      courseName: (map['course_name'] ?? '') as String,
      courseCode: (map['course_code'] ?? '') as String,
      totalSessions: (map['total_sessions'] as num? ?? 0).toInt(),
      attendedSessions: (map['attended_sessions'] as num? ?? 0).toInt(),
    );
  }

  bool get hasClasses => totalSessions > 0;

  // attended / total x 100  (0 when no class has been held yet)
  double get percentage =>
      hasClasses ? attendedSessions / totalSessions * 100 : 0;

  // Show the red warning only when classes exist and we are below 75%.
  bool get isBelowMinimum => hasClasses && percentage < minimumPercent;

  // How many classes in a row the student must attend to reach 75%.
  // From (attended + n) / (total + n) >= 0.75  ->  n >= 3 x total - 4 x attended
  int get classesNeededFor75 {
    final needed = 3 * totalSessions - 4 * attendedSessions;
    return needed > 0 ? needed : 0;
  }
}
