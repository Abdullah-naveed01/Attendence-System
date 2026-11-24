import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/audit_alert.dart';
import '../screens/teacher/alert_detail_screen.dart';
import '../screens/teacher/alerts_screen.dart';
import '../services/alert_service.dart';

// Bell icon for the Teacher Home app bar (teachers only; the admin gets
// no proxy alerts). Only alerts of the teacher's own courses count.
// - red badge = number of unread HIGH alerts (FR-37)
// - listens to Realtime; when a new high alert arrives it shows a red
//   banner with the student names and a "View" button (FR-36)
// It lives in the Home screen's app bar, so it keeps listening while
// other screens (e.g. the class session) are open on top of Home.
class AlertsButton extends StatefulWidget {
  const AlertsButton({super.key});

  @override
  State<AlertsButton> createState() => _AlertsButtonState();
}

class _AlertsButtonState extends State<AlertsButton> {
  final _service = AlertService();
  RealtimeChannel? _channel;
  int _unread = 0;

  // The teacher who opened this Home screen. A banner is shown only while
  // this same teacher is still logged in (never after a switch to the
  // admin or another account).
  final String? _teacherId = supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadCount();
    _channel = _service.listenHigh(_onNewAlert);
  }

  @override
  void dispose() {
    if (_channel != null) _service.stopListening(_channel!);
    super.dispose();
  }

  Future<void> _loadCount() async {
    try {
      final count = await _service.countUnreadHigh();
      if (mounted) setState(() => _unread = count);
    } catch (e) {
      // The badge is only a hint; the Alerts screen shows the real error.
      debugPrint('Could not count alerts: $e');
    }
  }

  void _onNewAlert(AuditAlert alert) {
    if (!mounted) return;
    // Someone else is logged in now: show nothing.
    if (supabase.auth.currentUser?.id != _teacherId) return;
    _loadCount();

    final owner = alert.ownerName != null
        ? '\nReal phone owner: ${alert.ownerName}'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 10),
        content: Text(
          '${alert.title} (${alert.courseCode ?? '-'})\n'
          'Account used: ${alert.accountName ?? '-'}$owner',
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () => _open(AlertDetailScreen(alert: alert)),
        ),
      ),
    );
  }

  Future<void> _open(Widget screen) async {
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _loadCount(); // alerts may have been read
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Alerts',
      onPressed: () => _open(const AlertsScreen()),
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        child: const Icon(Icons.notifications),
      ),
    );
  }
}
