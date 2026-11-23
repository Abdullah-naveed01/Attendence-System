import 'package:flutter/material.dart';

import '../../core/rpc_error.dart';
import '../../models/student_summary.dart';
import '../../services/admin_student_service.dart';
import '../../widgets/message_view.dart';
import '../../widgets/reset_device_dialog.dart';
import 'add_student_screen.dart';

// Admin: all students with their number of courses and phone status.
// Search, Add Student, and per student: Enroll in all class courses,
// Reset Device, Delete (permanent).
class AdminStudentsScreen extends StatefulWidget {
  const AdminStudentsScreen({super.key});

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  final _service = AdminStudentService();

  List<StudentSummary> _students = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _busyId; // student currently being enrolled or deleted

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
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

  // Students whose name or email contains the search text.
  List<StudentSummary> get _filtered {
    final text = _search.trim().toLowerCase();
    if (text.isEmpty) return _students;
    return _students
        .where((s) =>
            s.profile.fullName.toLowerCase().contains(text) ||
            s.profile.email.toLowerCase().contains(text))
        .toList();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------- Add Student ----------
  Future<void> _openAddStudent() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddStudentScreen()),
    );
    if (added == true && mounted) {
      _showMessage('Student added');
      _load();
    }
  }

  // ---------- Enroll in all class courses ----------
  Future<void> _enrollAll(StudentSummary student) async {
    setState(() => _busyId = student.profile.id);
    try {
      final added = await _service.enrollInAllClassCourses(student.profile.id);
      if (!mounted) return;
      _showMessage(added == 0
          ? '${student.displayName} is already in every class course.'
          : '${student.displayName} enrolled in $added more '
              'course${added == 1 ? '' : 's'}.');
      await _load();
    } catch (e) {
      if (mounted) _showMessage('Could not enroll: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ---------- Reset Device ----------
  Future<void> _resetDevice(StudentSummary student) async {
    final done = await confirmAndResetDevice(context,
        studentId: student.profile.id, studentName: student.displayName);
    if (done) _load();
  }

  // ---------- Delete Student (permanent) ----------
  Future<void> _confirmDelete(StudentSummary student) async {
    // First count the attendance records, so the dialog can show it.
    setState(() => _busyId = student.profile.id);
    int attendanceCount;
    try {
      attendanceCount = await _service.countAttendance(student.profile.id);
    } catch (e) {
      if (mounted) {
        setState(() => _busyId = null);
        _showMessage('Could not check attendance: ${friendlyError(e)}');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busyId = null);

    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${student.displayName}?'),
        content: Text(
          'This permanently deletes:\n'
          '- the login account (${student.profile.email})\n'
          '- $attendanceCount attendance '
          'record${attendanceCount == 1 ? '' : 's'}\n'
          '- ${student.courseCount} course '
          'enrollment${student.courseCount == 1 ? '' : 's'}\n\n'
          'Proxy alerts are kept, without the student\'s name.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _busyId = student.profile.id);
    try {
      final deleted = await _service.deleteStudent(student.profile.id);
      if (!mounted) return;
      _showMessage('${student.displayName} deleted '
          '($deleted attendance record${deleted == 1 ? '' : 's'} removed).');
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
      appBar: AppBar(title: const Text('Students')),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.person_add),
              label: const Text('Add Student'),
              onPressed: _openAddStudent,
            ),
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
    if (_students.isEmpty) {
      return const MessageView(
        icon: Icons.people_outline,
        message: 'No students yet. Tap "Add Student".',
      );
    }

    final list = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or email',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: list.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    MessageView(
                      icon: Icons.search_off,
                      message: 'No student matches your search.',
                    ),
                  ])
                : ListView.separated(
                    // space at the bottom so the button does not cover a row
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _buildTile(list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(StudentSummary student) {
    final busy = _busyId == student.profile.id;

    return ListTile(
      leading: Icon(
        student.hasPhone ? Icons.phone_android : Icons.phonelink_off,
        color: student.hasPhone ? Colors.green : Colors.grey,
      ),
      title: Text(student.displayName),
      subtitle: Text(
        '${student.profile.email}\n'
        '${student.courseCount} course${student.courseCount == 1 ? '' : 's'}'
        '  •  ${student.hasPhone ? 'Phone registered' : 'No phone registered'}',
      ),
      isThreeLine: true,
      trailing: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
              tooltip: 'Actions',
              enabled: _busyId == null,
              onSelected: (action) {
                switch (action) {
                  case 'enroll':
                    _enrollAll(student);
                  case 'reset':
                    _resetDevice(student);
                  case 'delete':
                    _confirmDelete(student);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'enroll',
                  child: ListTile(
                    leading: Icon(Icons.playlist_add_check),
                    title: Text('Enroll in all class courses'),
                  ),
                ),
                PopupMenuItem(
                  value: 'reset',
                  enabled: student.hasPhone,
                  child: const ListTile(
                    leading: Icon(Icons.phonelink_erase),
                    title: Text('Reset Device'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red),
                    title: Text('Delete student',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
    );
  }
}
