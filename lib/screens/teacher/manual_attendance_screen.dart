import 'package:flutter/material.dart';

import '../../core/rpc_error.dart';
import '../../models/course.dart';
import '../../models/profile.dart';
import '../../services/live_attendance_service.dart';
import '../../widgets/message_view.dart';

// "Mark manually" (FR-23): enrolled students who are NOT marked yet.
// The teacher taps a student, confirms, and the server function
// mark_manual saves a 'manual' row without a device_id.
// The live list on the session screen updates by itself (Realtime).
class ManualAttendanceScreen extends StatefulWidget {
  final String sessionId;
  final Course course;
  const ManualAttendanceScreen({
    super.key,
    required this.sessionId,
    required this.course,
  });

  @override
  State<ManualAttendanceScreen> createState() => _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState extends State<ManualAttendanceScreen> {
  final _service = LiveAttendanceService();

  List<Profile> _notMarked = [];
  bool _loading = true;
  String? _error;
  String? _savingId; // the student being saved right now

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Enrolled students minus the ones already present in this session.
  Future<void> _load() async {
    try {
      final enrolled = await _service.getEnrolledStudents(widget.course.id);
      final present = await _service.getPresent(widget.sessionId);
      final presentIds = present.map((p) => p.studentId).toSet();
      if (!mounted) return;
      setState(() {
        _notMarked =
            enrolled.where((s) => !presentIds.contains(s.id)).toList();
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

  Future<void> _mark(Profile student) async {
    final name = _nameOf(student);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark present?'),
        content: Text('Mark $name present in ${widget.course.code}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Mark Present'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _savingId = student.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.markManual(widget.sessionId, student.id);
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('$name marked present.'),
      ));
      if (!mounted) return;
      setState(() => _notMarked.removeWhere((s) => s.id == student.id));
    } on RpcException catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(e.message),
      ));
      // Already marked (e.g. scanned the QR meanwhile): refresh the list.
      if (e.code == 'ALREADY_MARKED') _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text('Could not mark $name: ${friendlyError(e)}'),
      ));
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mark manually - ${widget.course.code}')),
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
      child: _notMarked.isEmpty
          ? ListView(children: const [
              SizedBox(height: 120),
              MessageView(
                icon: Icons.done_all,
                color: Colors.green,
                message: 'Every enrolled student is already marked present.',
              ),
            ])
          : ListView.separated(
              itemCount: _notMarked.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '${_notMarked.length} student(s) not marked yet. '
                      'Tap a student to mark them present.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return _buildTile(_notMarked[i - 1]);
              },
            ),
    );
  }

  Widget _buildTile(Profile student) {
    final saving = _savingId == student.id;
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(_nameOf(student)),
      subtitle: Text(student.email),
      trailing: saving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.how_to_reg, color: Colors.green),
      // One save at a time
      onTap: _savingId == null ? () => _mark(student) : null,
    );
  }
}
