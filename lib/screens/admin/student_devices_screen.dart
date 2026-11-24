import 'package:flutter/material.dart';

import '../../core/rpc_error.dart';
import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../services/student_service.dart';
import '../../widgets/reset_device_dialog.dart';
import '../../widgets/state_views.dart';

// Which students to show.
enum _DeviceFilter { all, registered, notRegistered }

// Admin: every student with their phone status.
// - "Registered" (green) + Reset Device, when profiles.device_id is set
// - "Not registered yet" (grey) when it is empty; the phone registers by
//   itself on the student's first successful QR scan (mark_attendance)
// Search by name/email, filter All / Registered / Not registered, and a
// count at the top ("18 of 25 registered").
// Only the admin can reset a phone (reset_device checks this on the server).
class StudentDevicesScreen extends StatefulWidget {
  const StudentDevicesScreen({super.key});

  @override
  State<StudentDevicesScreen> createState() => _StudentDevicesScreenState();
}

class _StudentDevicesScreenState extends State<StudentDevicesScreen> {
  final _service = StudentService();

  List<Profile> _students = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  _DeviceFilter _filter = _DeviceFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // RLS: the admin gets every student.
      final students = await _service.getStudents();
      if (!mounted) return;
      setState(() {
        _students = students;
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

  String _nameOf(Profile s) => s.fullName.isEmpty ? s.email : s.fullName;

  // Search text + filter applied to the list
  List<Profile> get _visible {
    final text = _search.trim().toLowerCase();
    return _students.where((s) {
      final matchesText = text.isEmpty ||
          s.fullName.toLowerCase().contains(text) ||
          s.email.toLowerCase().contains(text);
      final hasPhone = s.deviceId != null;
      final matchesFilter = switch (_filter) {
        _DeviceFilter.all => true,
        _DeviceFilter.registered => hasPhone,
        _DeviceFilter.notRegistered => !hasPhone,
      };
      return matchesText && matchesFilter;
    }).toList();
  }

  Future<void> _reset(Profile student) async {
    final done = await confirmAndResetDevice(context,
        studentId: student.id, studentName: _nameOf(student));
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Devices')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
    if (_students.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        message: 'No students yet.',
      );
    }

    final registered = _students.where((s) => s.deviceId != null).length;
    final list = _visible;

    return Column(
      children: [
        // ---------- Count + search + filter ----------
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.phone_android, color: AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$registered of ${_students.length} registered',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name or email',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<_DeviceFilter>(
                segments: const [
                  ButtonSegment(
                      value: _DeviceFilter.all, label: Text('All')),
                  ButtonSegment(
                      value: _DeviceFilter.registered,
                      label: Text('Registered')),
                  ButtonSegment(
                      value: _DeviceFilter.notRegistered,
                      label: Text('Not registered')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ---------- List ----------
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: list.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.search_off,
                      message: 'No student matches your search or filter.',
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

  Widget _buildTile(Profile student) {
    final hasPhone = student.deviceId != null;
    final color = hasPhone ? AppColors.success : Colors.grey;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          hasPhone ? Icons.phone_android : Icons.phonelink_off,
          color: color,
        ),
      ),
      title: Text(_nameOf(student)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(student.email),
          const SizedBox(height: 2),
          Text(
            hasPhone
                ? 'Registered'
                : 'Not registered yet (registers on first QR scan)',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: hasPhone
          ? OutlinedButton(
              onPressed: () => _reset(student),
              child: const Text('Reset Device'),
            )
          : null,
    );
  }
}
