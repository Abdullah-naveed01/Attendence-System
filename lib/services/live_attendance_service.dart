import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/rpc_error.dart';
import '../core/supabase_client.dart';
import '../models/live_attendee.dart';
import '../models/profile.dart';

// Reads the attendance of one running class and listens for changes.
// RLS makes sure a teacher only gets rows of their own courses.
class LiveAttendanceService {
  // Everyone marked present in this session, newest first,
  // with the student's name and email from profiles.
  Future<List<LiveAttendee>> getPresent(String sessionId) async {
    final rows = await supabase
        .from('attendance')
        .select('student_id, method, marked_at, profiles(full_name, email)')
        .eq('session_id', sessionId)
        .order('marked_at', ascending: false);

    return rows
        .map((row) => LiveAttendee.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  // How many students are enrolled in this course (the "Y" in "X / Y").
  Future<int> countEnrolled(String courseId) async {
    final response = await supabase
        .from('enrollments')
        .select('id')
        .eq('course_id', courseId)
        .count(CountOption.exact);
    return response.count;
  }

  // All students enrolled in this course, sorted by name.
  Future<List<Profile>> getEnrolledStudents(String courseId) async {
    final rows = await supabase
        .from('enrollments')
        .select('profiles(id, full_name, email, role, device_id)')
        .eq('course_id', courseId);

    final students = rows
        .where((row) => row['profiles'] != null)
        .map((row) =>
            Profile.fromMap(Map<String, dynamic>.from(row['profiles'] as Map)))
        .toList();
    students.sort((a, b) =>
        a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return students;
  }

  // Marks one student present by hand. The server (mark_manual) checks
  // the teacher, the enrollment and duplicates, and saves the row with
  // method 'manual' and no device_id.
  Future<void> markManual(String sessionId, String studentId) async {
    final data = await supabase.rpc('mark_manual', params: {
      'p_session_id': sessionId,
      'p_student_id': studentId,
    });
    if (data is Map && data['ok'] == true) return;
    throw RpcException(
        (data is Map ? data['code'] : null)?.toString() ?? 'SERVER_ERROR');
  }

  // Calls onChange whenever an attendance row of this session changes
  // (for example, a student scans the QR).
  // Returns the channel so the screen can close it with stopListening().
  RealtimeChannel listen(String sessionId, void Function() onChange) {
    return supabase
        .channel('attendance-$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<void> stopListening(RealtimeChannel channel) async {
    await supabase.removeChannel(channel);
  }
}
