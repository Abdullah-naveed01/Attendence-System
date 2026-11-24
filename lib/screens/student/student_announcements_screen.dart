import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/date_format.dart';
import '../../core/rpc_error.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../models/announcement.dart';
import '../../models/course.dart';
import '../../services/announcement_service.dart';
import '../../services/course_service.dart';
import '../../widgets/state_views.dart';

// Student: announcements grouped by subject.
// - one expandable card per enrolled course (name + code as the header)
// - inside, the course's announcements, latest on top
// - "No announcements" for a course without any
// - new announcements appear live (Realtime), expired ones never show
// Opening this screen marks everything as seen (resets the Home badge).
class StudentAnnouncementsScreen extends StatefulWidget {
  const StudentAnnouncementsScreen({super.key});

  @override
  State<StudentAnnouncementsScreen> createState() =>
      _StudentAnnouncementsScreenState();
}

class _StudentAnnouncementsScreenState
    extends State<StudentAnnouncementsScreen> {
  final _service = AnnouncementService();
  final _courseService = CourseService();

  RealtimeChannel? _channel;
  List<Course> _courses = [];
  List<Announcement> _announcements = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // Live: reload when a teacher posts, edits or deletes.
    _channel = _service.listen('announcements-student', _load);
  }

  @override
  void dispose() {
    if (_channel != null) _service.stopListening(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final courses = await _courseService.getStudentCourses(userId);
      final announcements = await _service.getMyAnnouncements();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _announcements = announcements;
        _loading = false;
        _error = null;
      });
      // Everything on screen has now been seen.
      await _service.markAllSeen();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  // The not-expired announcements of one course, latest first.
  List<Announcement> _of(Course course) {
    final now = DateTime.now();
    final list = _announcements
        .where((a) => a.courseId == course.id && !a.isExpiredAt(now))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView(message: 'Loading announcements...');
    if (_error != null) {
      return ErrorState(
        message: _error!,
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }
    if (_courses.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        message: 'You are not enrolled in any course yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _courses.length,
        itemBuilder: (_, i) => _buildCourseSection(_courses[i]),
      ),
    );
  }

  // One subject: header (name + code + count), then its announcements.
  Widget _buildCourseSection(Course course) {
    final theme = Theme.of(context);
    final items = _of(course);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Open the subjects that have something to read
        initiallyExpanded: items.isNotEmpty,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.campaign_outlined,
              color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(course.name, style: theme.textTheme.titleMedium),
        subtitle: Text(course.code),
        trailing: items.isEmpty
            ? null
            : Badge(
                label: Text('${items.length}'),
                backgroundColor: theme.colorScheme.primary,
              ),
        childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        children: items.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'No announcements',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ]
            : items.map(_buildAnnouncement).toList(),
      ),
    );
  }

  Widget _buildAnnouncement(Announcement a) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(a.message),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.person_outline,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${a.teacherName.isEmpty ? 'Teacher' : a.teacherName}'
                  '  •  ${formatPakistanDateTime(a.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
