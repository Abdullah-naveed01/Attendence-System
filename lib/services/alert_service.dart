import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/audit_alert.dart';

// Reads proxy alerts (audit_logs) and listens for new ones.
//
// Proxy alerts go ONLY to the teacher of the course where the attempt
// happened (never to the admin or to other teachers).
// Two layers make sure of that:
//   1. RLS on audit_logs (sql/alerts_teacher_only.sql): only the course's
//      teacher can read or mark an alert.
//   2. Every query below also asks only for alerts of courses whose
//      teacher_id is the logged-in teacher.
class AlertService {
  // audit_logs has TWO links to profiles (account_id and device_owner_id),
  // so each join names the foreign key it should use.
  // courses!inner = only alerts that belong to a course.
  static const _select = '*, '
      'account:profiles!audit_logs_account_id_fkey(full_name), '
      'owner:profiles!audit_logs_device_owner_id_fkey(full_name), '
      'courses!inner(code, teacher_id)';

  // The logged-in teacher's id.
  String get _myId => supabase.auth.currentUser!.id;

  // Newest alerts of MY courses first (the latest 200 are enough).
  Future<List<AuditAlert>> getAlerts() async {
    final rows = await supabase
        .from('audit_logs')
        .select(_select)
        .eq('courses.teacher_id', _myId)
        .order('created_at', ascending: false)
        .limit(200);
    return rows
        .map((row) => AuditAlert.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  // One alert with names (used when Realtime reports a new row).
  // Returns null if it is not an alert of MY courses.
  Future<AuditAlert?> getAlert(String id) async {
    final row = await supabase
        .from('audit_logs')
        .select(_select)
        .eq('id', id)
        .eq('courses.teacher_id', _myId)
        .maybeSingle();
    if (row == null) return null;
    return AuditAlert.fromMap(Map<String, dynamic>.from(row));
  }

  // Number of unread high-severity alerts of MY courses (red badge).
  Future<int> countUnreadHigh() async {
    final response = await supabase
        .from('audit_logs')
        .select('id, courses!inner(teacher_id)')
        .eq('courses.teacher_id', _myId)
        .eq('severity', 'high')
        .eq('is_read', false)
        .count(CountOption.exact);
    return response.count;
  }

  // Only the is_read column may be changed by the app (database grant).
  Future<void> markRead(String id) async {
    await supabase.from('audit_logs').update({'is_read': true}).eq('id', id);
  }

  // Calls onChange for every new alert row (any severity).
  RealtimeChannel listenAll(void Function() onChange) {
    return supabase
        .channel('alerts-all')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'audit_logs',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  // Calls onNewAlert for every new HIGH-severity alert of MY courses, with
  // the names already looked up, so the banner can say who was involved.
  // (Realtime only delivers rows RLS lets this teacher read; getAlert
  // checks the course's teacher once more.)
  RealtimeChannel listenHigh(void Function(AuditAlert alert) onNewAlert) {
    return supabase
        .channel('alerts-high')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'audit_logs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'severity',
            value: 'high',
          ),
          callback: (payload) async {
            try {
              final id = payload.newRecord['id'].toString();
              final alert = await getAlert(id);
              if (alert != null) onNewAlert(alert); // only MY courses
            } catch (e) {
              debugPrint('Could not load the new alert: $e');
            }
          },
        )
        .subscribe();
  }

  Future<void> stopListening(RealtimeChannel channel) async {
    await supabase.removeChannel(channel);
  }
}
