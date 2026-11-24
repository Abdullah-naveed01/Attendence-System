import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/csv.dart';
import '../../core/date_format.dart';
import '../../core/rpc_error.dart';
import '../../core/theme.dart';
import '../../models/attendance_record_models.dart';
import '../../models/course.dart';
import '../../services/attendance_records_service.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_chip.dart';

// Teacher: every enrolled student's status on ONE class day.
// Tap a student to change their status (Present / Late / Absent /
// Excused). The server never deletes attendance: it updates the row or
// adds a manual one, and saves who edited it and when.
class AttendanceDayScreen extends StatefulWidget {
  final Course course;
  final ClassDay day;

  const AttendanceDayScreen({
    super.key,
    required this.course,
    required this.day,
  });

  @override
  State<AttendanceDayScreen> createState() => _AttendanceDayScreenState();
}

class _AttendanceDayScreenState extends State<AttendanceDayScreen> {
  final _service = AttendanceRecordsService();

  List<DayRecord> _records = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _savingId; // student being saved

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records =
          await _service.getDayRecords(widget.course.id, widget.day.date);
      if (!mounted) return;
      setState(() {
        _records = records;
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

  List<DayRecord> get _visible {
    final text = _search.trim().toLowerCase();
    if (text.isEmpty) return _records;
    return _records
        .where((r) =>
            r.fullName.toLowerCase().contains(text) ||
            r.email.toLowerCase().contains(text))
        .toList();
  }

  // ---------- Edit one student's status ----------
  Future<void> _edit(DayRecord record) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _EditStatusDialog(record: record),
    );
    if (result == null || !mounted) return;
    final (newStatus, reason) = result;
    if (newStatus == record.status) return;

    // Confirm before saving
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save change?'),
        content: Text('${record.displayName} on '
            '${formatDate(widget.day.date)}:\n'
            '${statusLabel(record.status)}  ->  ${statusLabel(newStatus)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _savingId = record.studentId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.editAttendance(
        sessionId: record.sessionId,
        studentId: record.studentId,
        status: newStatus,
        reason: reason,
      );
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text('${record.displayName}: ${statusLabel(newStatus)}'),
      ));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('Could not save: ${friendlyError(e)}'),
      ));
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  // ---------- Export this day as CSV ----------
  Future<void> _export() async {
    final rows = _records
        .map((r) => [
              formatDate(widget.day.date),
              r.displayName,
              r.email,
              statusLabel(r.status),
              r.method == null ? '' : (r.method == 'qr' ? 'QR' : 'Manual'),
              r.editedByName ?? '',
              r.editReason ?? '',
            ])
        .toList();
    final csv = toCsv(
        ['Date', 'Student', 'Email', 'Status', 'Method', 'Edited by', 'Reason'],
        rows);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Copied as CSV. Paste into Excel or Google Sheets.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final attended = _records
        .where((r) => r.status == 'present' || r.status == 'late')
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.course.code} - ${formatDate(widget.day.date)}'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Copy this day as CSV',
              onPressed: _export,
            ),
        ],
      ),
      body: _buildBody(attended),
    );
  }

  Widget _buildBody(int attended) {
    if (_loading) return const LoadingView(message: 'Loading students...');
    if (_error != null) {
      return ErrorState(
        message: _error!,
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }
    if (_records.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        message: 'No students are enrolled in this course.',
      );
    }

    final list = _visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Present $attended / ${_records.length}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search student',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: list.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.search_off,
                      message: 'No student matches your search.',
                    ),
                  ])
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _buildTile(list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(DayRecord r) {
    final theme = Theme.of(context);
    final saving = _savingId == r.studentId;

    final details = <String>[
      r.email,
      if (r.method != null) r.method == 'qr' ? 'QR' : 'Manual',
      if (r.editedAt != null)
        'Edited by ${r.editedByName ?? 'teacher'} on '
            '${formatPakistanDateTime(r.editedAt!)}'
            '${(r.editReason ?? '').isEmpty ? '' : ' - ${r.editReason}'}',
    ];

    return ListTile(
      title: Text(r.displayName),
      subtitle: Text(details.join('\n'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      isThreeLine: details.length > 2,
      trailing: saving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
          : StatusChip(status: r.status),
      onTap: _savingId == null ? () => _edit(r) : null,
    );
  }
}

// Pick the new status (+ optional reason). Pops with (status, reason).
class _EditStatusDialog extends StatefulWidget {
  final DayRecord record;
  const _EditStatusDialog({required this.record});

  @override
  State<_EditStatusDialog> createState() => _EditStatusDialogState();
}

class _EditStatusDialogState extends State<_EditStatusDialog> {
  late String _status = attendanceStatuses.contains(widget.record.status)
      ? widget.record.status
      : 'absent';
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.record.displayName),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _status,
              onChanged: (v) => setState(() => _status = v ?? _status),
              child: Column(
                children: [
                  for (final s in attendanceStatuses)
                    RadioListTile<String>(
                      value: s,
                      contentPadding: EdgeInsets.zero,
                      title: Row(children: [StatusChip(status: s)]),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _reason,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_status, _reason.text)),
          child: const Text('Next'),
        ),
      ],
    );
  }
}
