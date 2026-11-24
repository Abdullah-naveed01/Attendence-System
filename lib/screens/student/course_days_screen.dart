import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../core/rpc_error.dart';
import '../../core/theme.dart';
import '../../models/attendance_record_models.dart';
import '../../models/course_attendance.dart';
import '../../services/attendance_service.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_chip.dart';

// Student: ONE course, one line per class day (newest first) with
// Present / Late / Absent / Excused, and "Marked by teacher" when the
// teacher marked or edited it. Same day-based numbers as My Attendance.
class CourseDaysScreen extends StatefulWidget {
  final CourseAttendance course;
  const CourseDaysScreen({super.key, required this.course});

  @override
  State<CourseDaysScreen> createState() => _CourseDaysScreenState();
}

class _CourseDaysScreenState extends State<CourseDaysScreen> {
  final _service = AttendanceService();

  List<StudentDay> _days = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final days = await _service.getMyCourseDays(widget.course.courseId);
      if (!mounted) return;
      setState(() {
        _days = days;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.course.courseCode)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ErrorState(
        message: _error!,
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }

    final c = widget.course;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Course header with the same numbers as My Attendance
          Card(
            child: ListTile(
              title: Text(c.courseName,
                  style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(c.hasClasses
                  ? 'Attended ${c.attendedSessions} of ${c.totalSessions} classes'
                  : 'No classes held yet'),
              trailing: Text(
                c.hasClasses ? '${c.percentage.toStringAsFixed(0)}%' : '--',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: !c.hasClasses
                      ? Colors.grey
                      : (c.isBelowMinimum ? AppColors.danger : AppColors.success),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_days.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xl),
              child: EmptyState(
                icon: Icons.event_busy,
                message: 'No classes held for this course yet.',
              ),
            ),
          ..._days.map(_buildDay),
        ],
      ),
    );
  }

  Widget _buildDay(StudentDay d) {
    final theme = Theme.of(context);
    final lines = <String>[
      if (d.markedAt != null &&
          (d.status == 'present' || d.status == 'late'))
        'Marked at ${formatPakistanTime(d.markedAt!)}'
            '${d.method == 'qr' ? ' (QR)' : ''}',
      if (d.markedByTeacher) 'Marked by teacher',
      if (d.status == 'in_progress') 'Class is running - scan the QR',
    ];

    return Card(
      child: ListTile(
        leading: Icon(Icons.event, color: statusColor(d.status)),
        title: Text(formatDate(d.date)),
        subtitle: lines.isEmpty
            ? null
            : Text(lines.join('\n'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        trailing: StatusChip(status: d.status),
      ),
    );
  }
}
