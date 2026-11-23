import '../core/supabase_client.dart';
import '../models/course_attendance.dart';
import '../models/marked_class.dart';
import '../models/session_record.dart';

// The server's answer to mark_attendance.
class MarkResult {
  final String code; // MARKED, INVALID_QR, DEVICE_BLOCKED, ...
  final Map<String, dynamic> data; // the full response (may include extra info)

  MarkResult(this.code, this.data);

  bool get isMarked => code == 'MARKED';
}

// Attendance calls. The app sends only the QR token and the Android ID;
// the server decides whether the attendance is valid.
class AttendanceService {
  Future<MarkResult> markAttendance(String qrToken, String? deviceId) async {
    final result = await supabase.rpc('mark_attendance', params: {
      'p_token': qrToken,
      'p_device_id': deviceId,
    });

    if (result is! Map) {
      throw FormatException(
          'mark_attendance returned an unexpected response: $result');
    }
    final data = Map<String, dynamic>.from(result);
    return MarkResult((data['code'] ?? 'UNKNOWN').toString(), data);
  }

  // The class the student's attendance was just marked for
  // (course code, name, teacher, time). Returns null if it cannot be read,
  // so the result screen still works without these details.
  Future<MarkedClass?> getMyLastAttendance() async {
    try {
      final rows = await supabase.rpc('get_my_last_attendance') as List;
      if (rows.isEmpty) return null;
      return MarkedClass.fromMap(Map<String, dynamic>.from(rows.first));
    } catch (_) {
      return null; // e.g. sql/last_attendance_info.sql not run yet
    }
  }

  // The logged-in student's attendance numbers for each enrolled course.
  // Calculated on the server by get_my_attendance_summary()
  // (see sql/step4_student_attendance.sql).
  Future<List<CourseAttendance>> getMySummary() async {
    final rows = await supabase.rpc('get_my_attendance_summary') as List;
    return rows
        .map((row) => CourseAttendance.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  // Every class of one course, newest first, with Present / Absent.
  Future<List<SessionRecord>> getMyHistory(String courseId) async {
    final rows = await supabase.rpc(
      'get_my_course_history',
      params: {'p_course_id': courseId},
    ) as List;
    return rows
        .map((row) => SessionRecord.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }
}
