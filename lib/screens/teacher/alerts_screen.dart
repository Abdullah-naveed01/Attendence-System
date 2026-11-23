import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/date_format.dart';
import '../../core/rpc_error.dart';
import '../../models/audit_alert.dart';
import '../../services/alert_service.dart';
import '../../widgets/message_view.dart';
import 'alert_detail_screen.dart';

// Alerts list for a TEACHER: only proxy attempts in their own courses
// (the admin has no alerts). Newest first; high severity in red,
// low in grey; unread in bold.
// The list reloads by itself when Realtime reports a new alert.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _service = AlertService();

  RealtimeChannel? _channel;
  List<AuditAlert> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _service.listenAll(_load);
  }

  @override
  void dispose() {
    if (_channel != null) _service.stopListening(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final alerts = await _service.getAlerts();
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _open(AuditAlert alert) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlertDetailScreen(alert: alert)),
    );
    _load(); // show it as read now
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return MessageView.error(_error!, onRetry: () {
        setState(() => _loading = true);
        _load();
      });
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: _alerts.isEmpty
          // ListView so "pull to refresh" also works when the list is empty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                MessageView(
                  icon: Icons.verified_user,
                  color: Colors.green,
                  message: 'No alerts. Nobody has tried to mark attendance '
                      'from another phone.',
                ),
              ],
            )
          : ListView.separated(
              itemCount: _alerts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _buildTile(_alerts[i]),
            ),
    );
  }

  Widget _buildTile(AuditAlert alert) {
    final color = alert.isHigh ? Colors.red : Colors.grey.shade600;
    final details = [
      'Account: ${alert.accountName ?? '-'}',
      if (alert.ownerId != null)
        '${alert.ownerLabel}: ${alert.ownerName}',
      '${alert.courseCode ?? '-'}  •  '
          '${formatDate(alert.createdAt)}  ${formatTime(alert.createdAt)}',
    ].join('\n');

    return ListTile(
      tileColor: alert.isRead ? null : color.withValues(alpha: 0.06),
      leading: Icon(
        alert.isHigh ? Icons.warning_amber : Icons.info_outline,
        color: color,
      ),
      title: Text(
        alert.title,
        style: TextStyle(
          color: color,
          fontWeight: alert.isRead ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Text(details),
      isThreeLine: true,
      // Small dot = not read yet
      trailing: alert.isRead
          ? null
          : Icon(Icons.circle, size: 12, color: color),
      onTap: () => _open(alert),
    );
  }
}
