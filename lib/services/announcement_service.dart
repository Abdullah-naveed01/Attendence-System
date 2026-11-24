import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/announcement.dart';

// Announcements: teachers post / edit / delete for their own courses,
// students read the ones of their enrolled courses (not expired).
// The rules are enforced by RLS on the server (sql/announcements.sql).
class AnnouncementService {
  String get _myId => supabase.auth.currentUser!.id;

  // ---------- Teacher ----------

  // The logged-in teacher's announcements, newest first.
  Future<List<Announcement>> getTeacherAnnouncements(String teacherName) async {
    final rows = await supabase
        .from('announcements')
        .select('*, courses(code, name)')
        .eq('teacher_id', _myId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => Announcement.fromTeacherRow(
            Map<String, dynamic>.from(row), teacherName))
        .toList();
  }

  // created_at and expires_at (+7 days) are set by the database.
  Future<void> post({
    required String courseId,
    required String title,
    required String message,
  }) async {
    await supabase.from('announcements').insert({
      'course_id': courseId,
      'teacher_id': _myId,
      'title': title.trim(),
      'message': message.trim(),
    });
  }

  Future<void> edit({
    required String id,
    required String title,
    required String message,
  }) async {
    await supabase
        .from('announcements')
        .update({'title': title.trim(), 'message': message.trim()})
        .eq('id', id);
  }

  Future<void> delete(String id) async {
    await supabase.from('announcements').delete().eq('id', id);
  }

  // ---------- Student ----------

  // Announcements of my enrolled courses that have not expired, newest
  // first, with the teacher's name.
  Future<List<Announcement>> getMyAnnouncements() async {
    final rows = await supabase.rpc('get_my_announcements') as List;
    return rows
        .map((row) =>
            Announcement.fromStudentRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  // ---------- Live updates ----------

  // Calls onChange whenever an announcement is posted, edited or deleted.
  // RLS decides which new rows this user is told about.
  RealtimeChannel listen(String channelName, void Function() onChange) {
    return supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'announcements',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<void> stopListening(RealtimeChannel channel) async {
    await supabase.removeChannel(channel);
  }

  // ---------- "Last seen" (saved on this phone, per user) ----------

  String get _lastSeenKey => 'announcements_last_seen_$_myId';

  // When this user last opened the Announcements screen (null = never).
  Future<DateTime?> getLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_lastSeenKey);
    return text == null ? null : DateTime.tryParse(text);
  }

  Future<void> markAllSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _lastSeenKey, DateTime.now().toUtc().toIso8601String());
  }

  // How many of [list] were posted after the last visit.
  static int countNew(List<Announcement> list, DateTime? lastSeen) {
    if (lastSeen == null) return list.length;
    return list.where((a) => a.createdAt.isAfter(lastSeen)).length;
  }
}
