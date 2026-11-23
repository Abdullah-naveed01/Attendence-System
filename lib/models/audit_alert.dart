// One row of audit_logs, with the names already looked up:
// - account   = the student account that was logged in (account_id)
// - phone owner = the student the phone is registered to (device_owner_id)
class AuditAlert {
  final String id;
  final String eventType; // e.g. DEVICE_MISMATCH
  final String severity; // 'high' or 'low'
  final bool isRead;
  final DateTime createdAt;
  final String? accountId;
  final String? accountName;
  final String? ownerId;
  final String? ownerName;
  final String? courseCode;
  final String? deviceId;

  AuditAlert({
    required this.id,
    required this.eventType,
    required this.severity,
    required this.isRead,
    required this.createdAt,
    this.accountId,
    this.accountName,
    this.ownerId,
    this.ownerName,
    this.courseCode,
    this.deviceId,
  });

  bool get isHigh => severity == 'high';

  // Human-readable event name.
  String get title => alertTitle(eventType);

  // True for the events where someone tried to use a phone that is not theirs.
  bool get isDeviceProblem =>
      eventType == 'DEVICE_MISMATCH' ||
      eventType == 'DEVICE_ALREADY_BOUND' ||
      eventType == 'DEVICE_MULTI_STUDENT';

  // In a DEVICE_RESET row, device_owner_id holds the person who did the reset.
  String get ownerLabel =>
      eventType == 'DEVICE_RESET' ? 'Reset by' : 'Real phone owner';

  // Builds an alert from audit_logs + the joined names:
  //   account:profiles!audit_logs_account_id_fkey(full_name)
  //   owner:profiles!audit_logs_device_owner_id_fkey(full_name)
  //   courses(code)
  factory AuditAlert.fromMap(Map<String, dynamic> map) {
    final account = map['account'] as Map?;
    final owner = map['owner'] as Map?;
    final course = map['courses'] as Map?;
    final accountId = map['account_id'] as String?;
    final ownerId = map['device_owner_id'] as String?;

    return AuditAlert(
      id: map['id'] as String,
      eventType: (map['event_type'] ?? '').toString(),
      severity: (map['severity'] ?? 'low').toString(),
      isRead: map['is_read'] == true,
      createdAt: DateTime.parse(map['created_at'].toString()),
      accountId: accountId,
      accountName: _nameOf(accountId, account),
      ownerId: ownerId,
      ownerName: _nameOf(ownerId, owner),
      courseCode: course?['code']?.toString(),
      deviceId: map['device_id'] as String?,
    );
  }

  // RLS only lets a teacher read the profiles of their own students.
  // If the name is hidden, say so instead of showing nothing.
  static String? _nameOf(String? id, Map? profile) {
    if (id == null) return null;
    final name = profile?['full_name']?.toString() ?? '';
    return name.isEmpty ? 'Student outside your courses' : name;
  }
}

// Event code -> text shown to teachers and admins.
String alertTitle(String eventType) {
  switch (eventType) {
    case 'DEVICE_MISMATCH':
      return "Attempt from another student's phone";
    case 'DEVICE_ALREADY_BOUND':
      return 'Phone already registered to another student';
    case 'DEVICE_MULTI_STUDENT':
      return 'Same phone used for two students';
    case 'DUPLICATE_ATTEMPT':
      return 'Tried to mark attendance twice';
    case 'INVALID_QR':
      return 'Expired or invalid QR';
    case 'NOT_ENROLLED':
      return 'Not enrolled';
    case 'DEVICE_RESET':
      return 'Device reset';
    default:
      return eventType;
  }
}
