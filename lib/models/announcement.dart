// One announcement from a teacher to the students of one course.
// It disappears 7 days after it was posted (expires_at).
class Announcement {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String title;
  final String message;
  final String teacherName;
  final DateTime createdAt;
  final DateTime expiresAt;

  Announcement({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.title,
    required this.message,
    required this.teacherName,
    required this.createdAt,
    required this.expiresAt,
  });

  // Student rows from get_my_announcements() (already has course + teacher).
  factory Announcement.fromStudentRow(Map<String, dynamic> map) {
    return Announcement(
      id: map['id'] as String,
      courseId: map['course_id'] as String,
      courseCode: (map['course_code'] ?? '').toString(),
      courseName: (map['course_name'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      teacherName: (map['teacher_name'] ?? '').toString(),
      createdAt: DateTime.parse(map['created_at'].toString()),
      expiresAt: DateTime.parse(map['expires_at'].toString()),
    );
  }

  // Teacher rows from: announcements select *, courses(code, name)
  factory Announcement.fromTeacherRow(
      Map<String, dynamic> map, String teacherName) {
    final course = map['courses'] as Map?;
    return Announcement(
      id: map['id'] as String,
      courseId: map['course_id'] as String,
      courseCode: (course?['code'] ?? '').toString(),
      courseName: (course?['name'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      teacherName: teacherName,
      createdAt: DateTime.parse(map['created_at'].toString()),
      expiresAt: DateTime.parse(map['expires_at'].toString()),
    );
  }

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  // "Expires in 6 days", "Expires in 1 day", "Expires today", "Expired"
  String expiresText(DateTime now) {
    if (isExpiredAt(now)) return 'Expired';
    final hoursLeft = expiresAt.difference(now).inHours;
    if (hoursLeft < 24) return 'Expires today';
    final days = (hoursLeft / 24).ceil();
    return 'Expires in $days day${days == 1 ? '' : 's'}';
  }
}
