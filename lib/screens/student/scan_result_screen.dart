import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../models/marked_class.dart';

// How one server code is shown on screen.
class _ResultStyle {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final bool canScanAgain; // show a "Scan Again" button?

  const _ResultStyle(
      this.icon, this.color, this.title, this.message, this.canScanAgain);
}

// Full-screen result after scanning.
// Pops with `true` if the student taps "Scan Again", otherwise `false`.
class ScanResultScreen extends StatelessWidget {
  final String? code; // the server's code, e.g. 'MARKED' (null if no answer)
  final Map<String, dynamic> data; // the full server response
  final MarkedClass? markedClass; // which class it was marked for (MARKED only)
  final String? errorMessage; // set when the server could not be reached

  const ScanResultScreen({
    super.key,
    required this.code,
    required this.data,
    this.markedClass,
    this.errorMessage,
  });

  // One entry per mark_attendance code.
  // The server sends a precise code for each device problem
  // (DEVICE_MISMATCH, DEVICE_ALREADY_BOUND, DEVICE_MULTI_STUDENT);
  // the student sees one "blocked" message for all of them.
  _ResultStyle _styleFor(String? code) {
    switch (code) {
      case 'MARKED':
        return const _ResultStyle(Icons.check_circle, Colors.green,
            'Attendance Marked', 'Your attendance has been recorded.', false);
      case 'DEVICE_MISMATCH':
      case 'DEVICE_ALREADY_BOUND':
      case 'DEVICE_MULTI_STUDENT':
      case 'DEVICE_BLOCKED':
        return const _ResultStyle(
            Icons.phonelink_lock,
            Colors.red,
            'This phone is not registered to your account',
            'Attendance can only be marked from your own registered phone. '
                'This attempt has been reported to your teacher.\n\n'
                'If you changed or lost your phone, ask your teacher to reset your device.',
            false);
      case 'INVALID_QR':
        return const _ResultStyle(
            Icons.qr_code_2,
            Colors.orange,
            'QR expired, scan again',
            "The QR changes every 30 seconds. Scan the code that is on the teacher's screen right now.",
            true);
      case 'DUPLICATE_ATTEMPT':
      case 'ALREADY_MARKED':
        return const _ResultStyle(Icons.info, Colors.blue, 'Already Marked',
            'Your attendance for this class is already recorded.', false);
      case 'NOT_ENROLLED':
        return const _ResultStyle(
            Icons.block,
            Colors.red,
            'Not Enrolled',
            'You are not enrolled in this course. Contact your teacher or the admin.',
            false);
      case 'NO_DEVICE_ID':
        return const _ResultStyle(
            Icons.phone_android,
            Colors.red,
            'Phone Not Identified',
            "The app could not read this phone's ID. Close the app, open it again, and retry.",
            true);
      case 'NOT_AUTHENTICATED':
        return const _ResultStyle(Icons.lock, Colors.red, 'Session Expired',
            'Your login has expired. Please log out and log in again.', false);
      case 'NOT_ALLOWED':
        return const _ResultStyle(Icons.block, Colors.red, 'Not Allowed',
            'This account is not allowed to mark attendance.', false);
      default:
        return _ResultStyle(Icons.error, Colors.red, 'Something went wrong',
            'Unexpected server response: $code', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No server answer at all (e.g. no internet)
    final style = errorMessage != null
        ? _ResultStyle(Icons.wifi_off, Colors.red, 'Could not mark attendance',
            errorMessage!, true)
        : _styleFor(code);

    // Show the course name if the server sends it (optional).
    final courseName = data['course_name'] ?? data['course_code'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(style.icon, size: 120, color: style.color),
              const SizedBox(height: 16),
              Text(
                style.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: style.color,
                ),
              ),
              // Which class the attendance was marked for, e.g.
              // "CS-301 Mobile App Development / Ashfaq Ahmed / Marked at 10:32 PM"
              if (markedClass != null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          '${markedClass!.courseCode}  ${markedClass!.courseName}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (markedClass!.teacherName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(markedClass!.teacherName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16)),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Marked at ${formatPakistanTime(markedClass!.markedAt)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (courseName != null) ...[
                const SizedBox(height: 8),
                Text('$courseName',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18)),
              ],
              const SizedBox(height: 12),
              Text(
                style.message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              if (style.canScanAgain)
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan Again'),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
