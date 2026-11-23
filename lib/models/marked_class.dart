// The class a student's attendance was just marked for
// (from get_my_last_attendance(), see sql/last_attendance_info.sql).
class MarkedClass {
  final String courseCode;
  final String courseName;
  final String teacherName;
  final DateTime markedAt;

  MarkedClass({
    required this.courseCode,
    required this.courseName,
    required this.teacherName,
    required this.markedAt,
  });

  factory MarkedClass.fromMap(Map<String, dynamic> map) {
    return MarkedClass(
      courseCode: (map['course_code'] ?? '').toString(),
      courseName: (map['course_name'] ?? '').toString(),
      teacherName: (map['teacher_name'] ?? '').toString(),
      markedAt: DateTime.parse(map['marked_at'].toString()),
    );
  }
}
