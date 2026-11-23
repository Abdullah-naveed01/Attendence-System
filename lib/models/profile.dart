// Holds one row of the profiles table as a Dart object.
class Profile {
  final String id;
  final String fullName;
  final String email;
  final String role; // 'admin' | 'teacher' | 'student'
  final String? deviceId;

  Profile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.deviceId,
  });

  // Converts the Map returned by Supabase into a Profile object.
  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: (map['full_name'] ?? '') as String,
      email: (map['email'] ?? '') as String,
      role: (map['role'] ?? 'student') as String,
      deviceId: map['device_id'] as String?,
    );
  }
}
