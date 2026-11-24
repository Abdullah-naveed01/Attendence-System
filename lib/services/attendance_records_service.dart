import '../core/rpc_error.dart';
import '../core/supabase_client.dart';
import '../models/attendance_record_models.dart';

// Teacher / admin: day-based attendance records of a course.
// Every function on the server checks that the caller is the course's
// teacher or an admin (sql/attendance_records.sql).
class AttendanceRecordsService {
  // All class dates of a course, newest first, with "Present X / Y".
  Future<List<ClassDay>> getClassDays(String courseId) async {
    final rows = await supabase.rpc('get_course_class_days',
        params: {'p_course_id': courseId}) as List;
    return rows
        .map((r) => ClassDay.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  // Every enrolled student's status on one class day.
  Future<List<DayRecord>> getDayRecords(String courseId, DateTime date) async {
    final rows = await supabase.rpc('get_course_day_records', params: {
      'p_course_id': courseId,
      'p_class_date': _dateText(date),
    }) as List;
    return rows
        .map((r) => DayRecord.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  // Changes one student's status for one class day. The server updates
  // the existing row (never deletes) or adds a manual row, and records
  // who edited, when, and the reason.
  Future<void> editAttendance({
    required String sessionId,
    required String studentId,
    required String status,
    String? reason,
  }) async {
    final data = await supabase.rpc('edit_attendance', params: {
      'p_session_id': sessionId,
      'p_student_id': studentId,
      'p_status': status,
      'p_reason': reason,
    });
    if (data is Map && data['ok'] == true) return;
    throw RpcException(
        (data is Map ? data['code'] : null)?.toString() ?? 'SERVER_ERROR');
  }

  // 2026-11-24 (the format the server expects for a date)
  static String _dateText(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
