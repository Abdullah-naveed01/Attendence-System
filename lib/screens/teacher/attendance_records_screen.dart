import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/csv.dart';
import '../../core/date_format.dart';
import '../../core/rpc_error.dart';
import '../../core/theme.dart';
import '../../models/attendance_record_models.dart';
import '../../models/course.dart';
import '../../services/attendance_records_service.dart';
import '../../services/course_service.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_chip.dart';
import 'attendance_day_screen.dart';

// Teacher: "Attendance Records".
// Pick one of MY courses -> every class date (newest first) with
// "Present X / Y". Summary on top: total classes and average attendance.
// Tap a date to see / edit each student's status for that day.
// One entry per course per day (Pakistan date), same numbers as the
// students see.
class AttendanceRecordsScreen extends StatefulWidget {
  final String teacherId;
  const AttendanceRecordsScreen({super.key, required this.teacherId});

  @override
  State<AttendanceRecordsScreen> createState() =>
      _AttendanceRecordsScreenState();
}

class _AttendanceRecordsScreenState extends State<AttendanceRecordsScreen> {
  final _courseService = CourseService();
  final _service = AttendanceRecordsService();

  List<Course> _courses = [];
  Course? _course;
  bool _loadingCourses = true;

  List<ClassDay> _days = [];
  bool _loadingDays = false;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _loadingCourses = true;
      _error = null;
    });
    try {
      final courses = await _courseService.getTeacherCourses(widget.teacherId);
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _course = courses.isEmpty ? null : courses.first;
        _loadingCourses = false;
      });
      if (_course != null) _loadDays();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loadingCourses = false;
      });
    }
  }

  Future<void> _loadDays() async {
    final course = _course;
    if (course == null) return;
    setState(() {
      _loadingDays = true;
      _error = null;
    });
    try {
      final days = await _service.getClassDays(course.id);
      // Ignore the answer if the teacher switched course meanwhile
      if (!mounted || course.id != _course?.id) return;
      setState(() {
        _days = days;
        _loadingDays = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loadingDays = false;
      });
    }
  }

  Future<void> _openDay(ClassDay day) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceDayScreen(course: _course!, day: day),
      ),
    );
    _loadDays(); // statuses may have been edited
  }

  // Whole course as CSV: one line per student per date.
  Future<void> _exportCourse() async {
    final course = _course;
    if (course == null || _days.isEmpty) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = <List<String>>[];
      for (final day in _days) {
        final records = await _service.getDayRecords(course.id, day.date);
        for (final r in records) {
          rows.add([
            formatDate(day.date),
            r.displayName,
            r.email,
            statusLabel(r.status),
            r.method == null ? '' : (r.method == 'qr' ? 'QR' : 'Manual'),
          ]);
        }
      }
      final csv = toCsv(['Date', 'Student', 'Email', 'Status', 'Method'], rows);
      await Clipboard.setData(ClipboardData(text: csv));
      messenger.showSnackBar(SnackBar(
        content: Text('${course.code}: ${rows.length} lines copied as CSV. '
            'Paste into Excel or Google Sheets.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('Could not export: ${friendlyError(e)}'),
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Records'),
        actions: [
          if (_days.isNotEmpty)
            _exporting
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: 'Copy whole course as CSV',
                    onPressed: _exportCourse,
                  ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingCourses) return const LoadingView(message: 'Loading courses...');
    if (_courses.isEmpty && _error == null) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        message: 'You have no courses yet.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: DropdownButtonFormField<String>(
            initialValue: _course?.id,
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
            onChanged: (id) {
              setState(() {
                _course = _courses.firstWhere((c) => c.id == id);
                _days = [];
              });
              _loadDays();
            },
          ),
        ),
        Expanded(child: _buildDays()),
      ],
    );
  }

  Widget _buildDays() {
    if (_loadingDays) return const LoadingView();
    if (_error != null) {
      return ErrorState(
        message: _error!,
        onRetry: _courses.isEmpty ? _loadCourses : _loadDays,
      );
    }
    if (_days.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadDays,
        child: ListView(children: const [
          SizedBox(height: 80),
          EmptyState(
            icon: Icons.event_busy,
            message: 'No classes held for this course yet.',
          ),
        ]),
      );
    }

    // Summary: total classes and average attendance
    final attended = _days.fold<int>(0, (sum, d) => sum + d.attendedCount);
    final counted = _days.fold<int>(0, (sum, d) => sum + d.countedCount);
    final average = counted == 0 ? 0 : (attended * 100 / counted).round();

    return RefreshIndicator(
      onRefresh: _loadDays,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.event_available,
                  label: 'Total classes',
                  value: '${_days.length}',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: StatCard(
                  icon: Icons.percent,
                  label: 'Average attendance',
                  value: '$average%',
                  color: average >= 75 ? AppColors.success : AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._days.map(_buildDayTile),
        ],
      ),
    );
  }

  Widget _buildDayTile(ClassDay day) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Text('${day.date.day}'),
        ),
        title: Text(formatDate(day.date)),
        subtitle: Text(day.isActive
            ? 'Class running now'
            : 'Present ${day.attendedCount} / ${day.enrolledCount}'),
        trailing: day.isActive
            ? const StatusChip(status: 'in_progress')
            : const Icon(Icons.chevron_right),
        onTap: () => _openDay(day),
      ),
    );
  }
}
