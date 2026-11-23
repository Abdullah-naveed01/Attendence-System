// One row of get_my_course_history(): one class and whether the student attended.
class SessionRecord {
  final String sessionId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final bool isActive; // the class is still running
  final bool present;
  final String? method; // 'qr' or 'manual' (only when present)
  final DateTime? markedAt;

  SessionRecord({
    required this.sessionId,
    required this.startedAt,
    this.endedAt,
    required this.isActive,
    required this.present,
    this.method,
    this.markedAt,
  });

  factory SessionRecord.fromMap(Map<String, dynamic> map) {
    DateTime? parse(Object? value) =>
        value == null ? null : DateTime.parse(value as String);

    return SessionRecord(
      sessionId: map['session_id'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: parse(map['ended_at']),
      isActive: map['is_active'] == true,
      present: map['present'] == true,
      method: map['method'] as String?,
      markedAt: parse(map['marked_at']),
    );
  }
}
