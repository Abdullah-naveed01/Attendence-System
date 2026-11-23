// Form checks used by the admin screens.
// The Edge Function checks the same rules again on the server.

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? value) {
  if (value == null || !_emailPattern.hasMatch(value.trim())) {
    return 'Enter a valid email address';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.length < 8) {
    return 'Password must be at least 8 characters';
  }
  return null;
}

// The second password box must match the first one.
String? validateConfirmPassword(String? value, String password) {
  if (value == null || value.isEmpty) return 'Please type the password again';
  if (value != password) return 'Passwords do not match';
  return null;
}

String? validateRequired(String? value, String fieldName) {
  if (value == null || value.trim().isEmpty) return '$fieldName is required';
  return null;
}

// Course codes are stored in capital letters, e.g. "cs-401 " -> "CS-401".
String normalizeCourseCode(String code) => code.trim().toUpperCase();
