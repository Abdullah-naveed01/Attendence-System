// Models for the day-based attendance records
// (sql/attendance_records.sql, view student_daily_attendance).

// Teacher: one class date of a course, from get_course_class_days().
class ClassDay {
  final DateTime date; // the Pakistan date of the class
  final String sessionId; // the day's (first) session
  final bool isActive; // the class is still running
  final int attendedCount; // present + late
  final int countedCount; // present + late + absent
  final int enrolledCount;

  ClassDay({
    required this.date,
    required this.sessionId,
    required this.isActive,
    required this.attendedCount,
    required this.countedCount,
    required this.enrolledCount,
  });

  factory ClassDay.fromMap(Map<String, dynamic> map) {
    return ClassDay(
      date: DateTime.parse(map['class_date'].toString()),
      sessionId: map['session_id'].toString(),
      isActive: map['is_active'] == true,
      attendedCount: (map['attended_count'] as num? ?? 0).toInt(),
      countedCount: (map['counted_count'] as num? ?? 0).toInt(),
      enrolledCount: (map['enrolled_count'] as num? ?? 0).toInt(),
    );
  }
}

// Teacher: one enrolled student's status on one class day,
// from get_course_day_records().
class DayRecord {
  final String studentId;
  final String fullName;
  final String email;
  final String status; // present | late | absent | excused | in_progress
  final String? method; // qr | manual (null = no row that day)
  final DateTime? markedAt;
  final String? editedByName;
  final DateTime? editedAt;
  final String? editReason;
  final String sessionId; // the day's (first) session

  DayRecord({
    required this.studentId,
    required this.fullName,
    required this.email,
    required this.status,
    this.method,
    this.markedAt,
    this.editedByName,
    this.editedAt,
    this.editReason,
    required this.sessionId,
  });

  String get displayName => fullName.isEmpty ? email : fullName;

  factory DayRecord.fromMap(Map<String, dynamic> map) {
    DateTime? parse(Object? v) => v == null ? null : DateTime.parse(v.toString());
    return DayRecord(
      studentId: map['student_id'].toString(),
      fullName: (map['full_name'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      status: (map['status'] ?? 'absent').toString(),
      method: map['method']?.toString(),
      markedAt: parse(map['marked_at']),
      editedByName: map['edited_by_name']?.toString(),
      editedAt: parse(map['edited_at']),
      editReason: map['edit_reason']?.toString(),
      sessionId: map['session_id'].toString(),
    );
  }
}

// Student: one class day of one course, from get_my_course_days().
class StudentDay {
  final DateTime date;
  final String status;
  final String? method;
  final bool markedByTeacher; // manual or edited by the teacher
  final DateTime? markedAt;
  final bool isActive;

  StudentDay({
    required this.date,
    required this.status,
    this.method,
    required this.markedByTeacher,
    this.markedAt,
    required this.isActive,
  });

  factory StudentDay.fromMap(Map<String, dynamic> map) {
    return StudentDay(
      date: DateTime.parse(map['class_date'].toString()),
      status: (map['status'] ?? 'absent').toString(),
      method: map['method']?.toString(),
      markedByTeacher: map['marked_by_teacher'] == true,
      markedAt: map['marked_at'] == null
          ? null
          : DateTime.parse(map['marked_at'].toString()),
      isActive: map['is_active'] == true,
    );
  }
}
