import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Thrown when an RPC or Edge Function returns {ok: false, code: '...'},
// so the screen knows exactly what the server rejected.
// [detail] is the server's own explanation (Edge Functions send one).
class RpcException implements Exception {
  final String code;
  final String? detail;
  RpcException(this.code, [this.detail]);

  String get message => detail ?? rpcMessage(code);

  @override
  String toString() => message;
}

// Converts a server code into a message the user can understand.
String rpcMessage(String code) {
  switch (code) {
    case 'NOT_ALLOWED':
      return 'You are not allowed to do this (this is not your course).';
    case 'SESSION_NOT_ACTIVE':
      return 'This class has already ended.';
    case 'NOT_AUTHENTICATED':
      return 'Your login has expired. Please log out and log in again.';
    case 'NOT_SCHEDULED':
      return 'This class is not scheduled right now. '
          'You can start it only on its timetable day, '
          'between its start and end time (Pakistan time).';
    case 'NOT_ENROLLED':
      return 'This student is not enrolled in this course.';
    case 'ALREADY_MARKED':
      return 'This student is already marked present.';
    case 'NOT_ADMIN':
      return 'Only an admin can manage teachers and students.';
    case 'NOT_A_STUDENT':
      return 'This account is not a student.';
    case 'NO_CLASS_COURSES':
      return 'The timetable has no courses yet.';
    case 'EMAIL_EXISTS':
      return 'An account with this email already exists.';
    case 'COURSE_CODE_EXISTS':
      return 'This course code already exists.';
    case 'NOT_A_TEACHER':
      return 'This account is not a teacher.';
    default:
      return 'Server error: $code';
  }
}

// Converts any error into a clear message for the screen.
// Unknown errors show their real text, so problems are never hidden.
String friendlyError(Object error) {
  debugPrint('Error: $error');

  if (error is RpcException) return error.message;
  if (error is PostgrestException) return 'Database error: ${error.message}';
  if (error is AuthException) return error.message;

  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup')) {
    return 'No internet connection. Please check your connection and try again.';
  }
  return 'Unexpected error: $text';
}
