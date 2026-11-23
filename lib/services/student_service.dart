import '../core/rpc_error.dart';
import '../core/supabase_client.dart';
import '../models/profile.dart';

// Students list + "Reset Device".
// RLS decides which students are returned: a teacher gets the students
// of their own courses, an admin gets all students.
class StudentService {
  Future<List<Profile>> getStudents() async {
    final rows = await supabase
        .from('profiles')
        .select()
        .eq('role', 'student')
        .order('full_name');
    return rows.map((row) => Profile.fromMap(row)).toList();
  }

  // Removes the phone registered to this student, so the next phone they
  // scan with becomes their new phone. The server checks that the caller
  // is an admin or teaches this student, and writes a DEVICE_RESET log.
  Future<void> resetDevice(String studentId) async {
    final data = await supabase
        .rpc('reset_device', params: {'p_student_id': studentId});
    if (data is Map && data['ok'] == true) return;
    throw RpcException(
        (data is Map ? data['code'] : null)?.toString() ?? 'SERVER_ERROR');
  }
}
