// One student who is marked present in the running class.
class LiveAttendee {
  final String studentId;
  final String fullName;
  final String email;
  final String method; // 'qr' or 'manual'
  final DateTime markedAt;

  LiveAttendee({
    required this.studentId,
    required this.fullName,
    required this.email,
    required this.method,
    required this.markedAt,
  });

  // Builds one row from: attendance + the student's profile (joined).
  factory LiveAttendee.fromMap(Map<String, dynamic> map) {
    final profile = Map<String, dynamic>.from(map['profiles'] ?? {});
    return LiveAttendee(
      studentId: map['student_id'].toString(),
      fullName: (profile['full_name'] ?? 'Unknown student').toString(),
      email: (profile['email'] ?? '').toString(),
      method: (map['method'] ?? 'qr').toString(),
      markedAt: DateTime.parse(map['marked_at'].toString()),
    );
  }
}
