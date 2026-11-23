import 'profile.dart';

// One row of the admin's Students list.
class StudentSummary {
  final Profile profile;
  final int courseCount; // how many courses the student is enrolled in

  StudentSummary({required this.profile, required this.courseCount});

  String get displayName =>
      profile.fullName.isEmpty ? profile.email : profile.fullName;

  bool get hasPhone => profile.deviceId != null;
}
