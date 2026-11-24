import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../core/rpc_error.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../models/announcement.dart';
import '../../models/course.dart';
import '../../services/announcement_service.dart';
import '../../services/course_service.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/section_header.dart';
import '../../widgets/state_views.dart';

// Teacher: post an announcement to one of MY courses, and see / edit /
// delete my announcements (newest first). Each one disappears from
// students 7 days after it was posted.
class TeacherAnnouncementsScreen extends StatefulWidget {
  final String teacherId;
  final String teacherName;

  const TeacherAnnouncementsScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
  });

  @override
  State<TeacherAnnouncementsScreen> createState() =>
      _TeacherAnnouncementsScreenState();
}

class _TeacherAnnouncementsScreenState
    extends State<TeacherAnnouncementsScreen> {
  final _service = AnnouncementService();
  final _courseService = CourseService();

  // Post form
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  String? _courseId;
  bool _posting = false;
  String? _postError;

  // Data
  List<Course> _courses = [];
  List<Announcement> _announcements = [];
  bool _loading = true;
  String? _error;
  String? _busyId; // announcement being deleted

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final courses = await _courseService.getTeacherCourses(widget.teacherId);
      final announcements =
          await _service.getTeacherAnnouncements(widget.teacherName);
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _announcements = announcements;
        // Pick the first course by default
        _courseId ??= courses.isEmpty ? null : courses.first.id;
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

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------- Post ----------
  Future<void> _post() async {
    if (!_formKey.currentState!.validate() || _courseId == null) return;

    setState(() {
      _posting = true;
      _postError = null;
    });
    try {
      await _service.post(
        courseId: _courseId!,
        title: _titleController.text,
        message: _messageController.text,
      );
      if (!mounted) return;
      _titleController.clear();
      _messageController.clear();
      FocusScope.of(context).unfocus();
      _showMessage('Announcement posted');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _postError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  // ---------- Edit ----------
  Future<void> _edit(Announcement announcement) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EditAnnouncementDialog(announcement: announcement),
    );
    if (result == null || !mounted) return;

    setState(() => _busyId = announcement.id);
    try {
      await _service.edit(
          id: announcement.id, title: result.$1, message: result.$2);
      if (!mounted) return;
      _showMessage('Announcement updated');
      await _load();
    } catch (e) {
      if (mounted) _showMessage('Could not update: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ---------- Delete ----------
  Future<void> _delete(Announcement announcement) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
        title: const Text('Delete announcement?'),
        content: Text(
            '"${announcement.title}" will be removed for all students of '
            '${announcement.courseCode}. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _busyId = announcement.id);
    try {
      await _service.delete(announcement.id);
      if (!mounted) return;
      _showMessage('Announcement deleted');
      await _load();
    } catch (e) {
      if (mounted) _showMessage('Could not delete: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ---------- UI ----------
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
        message: 'You have no courses yet, so you cannot post announcements.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _buildPostForm(),
          SectionHeader(
            title: 'My announcements',
            subtitle: 'Each one is removed 7 days after posting',
          ),
          if (_announcements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: EmptyState(
                icon: Icons.campaign_outlined,
                message: 'You have not posted any announcements yet.',
              ),
            ),
          ..._announcements.map(_buildAnnouncementCard),
        ],
      ),
    );
  }

  Widget _buildPostForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New announcement',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _courseId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Course',
                  prefixIcon: Icon(Icons.menu_book_outlined),
                ),
                items: _courses
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.code}  ${c.name}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: _posting
                    ? null
                    : (id) => setState(() => _courseId = id),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _titleController,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) => validateRequired(v, 'Title'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _messageController,
                maxLength: 2000,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                ),
                validator: (v) => validateRequired(v, 'Message'),
              ),
              if (_postError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                ErrorBanner(message: _postError!),
              ],
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Post',
                icon: Icons.send_rounded,
                loading: _posting,
                onPressed: _post,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncementCard(Announcement a) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final busy = _busyId == a.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(a.courseCode),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    a.expiresText(now),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: a.isExpiredAt(now)
                          ? AppColors.danger
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                    onPressed: _busyId == null ? () => _edit(a) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.danger),
                    tooltip: 'Delete',
                    onPressed: _busyId == null ? () => _delete(a) : null,
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(a.message),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    formatPakistanDateTime(a.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Edit title + message. Pops with (title, message), or null on Cancel.
class _EditAnnouncementDialog extends StatefulWidget {
  final Announcement announcement;
  const _EditAnnouncementDialog({required this.announcement});

  @override
  State<_EditAnnouncementDialog> createState() =>
      _EditAnnouncementDialogState();
}

class _EditAnnouncementDialogState extends State<_EditAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.announcement.title);
  late final _message =
      TextEditingController(text: widget.announcement.message);

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit - ${widget.announcement.courseCode}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _title,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => validateRequired(v, 'Title'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _message,
                maxLength: 2000,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Message'),
                validator: (v) => validateRequired(v, 'Message'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (_title.text, _message.text));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
