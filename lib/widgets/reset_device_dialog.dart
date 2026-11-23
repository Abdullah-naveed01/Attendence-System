import 'package:flutter/material.dart';

import '../core/rpc_error.dart';
import '../services/student_service.dart';

// Asks "Reset device?", calls reset_device on the server, and shows the
// result in a SnackBar. Returns true if the device was reset.
// Used on the alert detail screen and on the students list.
Future<bool> confirmAndResetDevice(
  BuildContext context, {
  required String studentId,
  required String studentName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Reset device?'),
      content: Text(
        'The phone registered to $studentName will be removed.\n\n'
        'The next phone $studentName uses to scan a QR code becomes their '
        'registered phone. Do this only if the student really changed or '
        'lost their phone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Reset Device'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await StudentService().resetDevice(studentId);
    messenger.showSnackBar(SnackBar(
      backgroundColor: Colors.green,
      content: Text('Device reset for $studentName.'),
    ));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      backgroundColor: Colors.red,
      content: Text('Could not reset the device: ${friendlyError(e)}'),
    ));
    return false;
  }
}
