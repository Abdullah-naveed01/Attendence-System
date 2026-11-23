import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../models/audit_alert.dart';
import '../../services/alert_service.dart';
import '../../widgets/reset_device_dialog.dart';

// Full details of one alert (teacher and admin).
// Opening it marks the alert as read. For phone problems it offers
// "Reset Device" for the students involved.
class AlertDetailScreen extends StatefulWidget {
  final AuditAlert alert;
  const AlertDetailScreen({super.key, required this.alert});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  @override
  void initState() {
    super.initState();
    _markRead();
  }

  Future<void> _markRead() async {
    if (widget.alert.isRead) return;
    try {
      await AlertService().markRead(widget.alert.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not mark this alert as read. '
            'Check your internet connection.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final color = alert.isHigh ? Colors.red : Colors.grey.shade700;

    return Scaffold(
      appBar: AppBar(title: const Text('Alert')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header: icon + event name + severity
          Card(
            color: alert.isHigh ? Colors.red.shade50 : null,
            child: ListTile(
              leading: Icon(
                alert.isHigh ? Icons.warning_amber : Icons.info_outline,
                color: color,
                size: 36,
              ),
              title: Text(
                alert.title,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(alert.isHigh ? 'High severity' : 'Low severity'),
            ),
          ),
          const SizedBox(height: 8),
          _row('Account used', alert.accountName ?? '-'),
          if (alert.ownerId != null || alert.isDeviceProblem)
            _row(alert.ownerLabel,
                alert.ownerName ?? 'Not registered to any student'),
          _row('Course', alert.courseCode ?? '-'),
          _row('Date', formatDate(alert.createdAt)),
          _row('Time', formatTime(alert.createdAt)),
          if (alert.deviceId != null) _row('Phone ID', alert.deviceId!),
          if (alert.isDeviceProblem) ..._resetButtons(alert),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // One "Reset Device" button per student involved (account and owner).
  List<Widget> _resetButtons(AuditAlert alert) {
    final people = <String, String>{}; // student id -> name
    if (alert.accountId != null) {
      people[alert.accountId!] = alert.accountName ?? 'this student';
    }
    if (alert.ownerId != null) {
      people[alert.ownerId!] = alert.ownerName ?? 'this student';
    }

    return [
      const SizedBox(height: 16),
      const Text(
        'Only reset a phone if the student really changed or lost it.',
        style: TextStyle(color: Colors.grey),
      ),
      for (final entry in people.entries)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.phonelink_erase),
            label: Text('Reset Device of ${entry.value}'),
            onPressed: () => confirmAndResetDevice(
              context,
              studentId: entry.key,
              studentName: entry.value,
            ),
          ),
        ),
    ];
  }
}
