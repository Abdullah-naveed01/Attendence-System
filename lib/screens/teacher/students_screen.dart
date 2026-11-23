import 'package:flutter/material.dart';

import '../../core/rpc_error.dart';
import '../../models/profile.dart';
import '../../services/student_service.dart';
import '../../widgets/message_view.dart';
import '../../widgets/reset_device_dialog.dart';

// Students with their phone status and a "Reset Device" button.
// Teacher: students of their own courses. Admin: all students.
// (RLS on profiles decides who is visible.)
class StudentsScreen extends StatefulWidget {
  final String title;
  const StudentsScreen({super.key, required this.title});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _service = StudentService();

  List<Profile> _students = [];
  bool _loading = true;
  String? _error;
  String _search = '';

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
  List<Profile> get _filtered {
    final text = _search.trim().toLowerCase();
    if (text.isEmpty) return _students;
    return _students
        .where((s) =>
            s.fullName.toLowerCase().contains(text) ||
            s.email.toLowerCase().contains(text))
        .toList();
  }

  Future<void> _reset(Profile student) async {
    final name = student.fullName.isEmpty ? student.email : student.fullName;
    final done = await confirmAndResetDevice(context,
        studentId: student.id, studentName: name);
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
        message: 'No students found.',
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
    return ListTile(
      leading: Icon(
        hasPhone ? Icons.phone_android : Icons.phonelink_off,
        color: hasPhone ? Colors.green : Colors.grey,
      ),
      title: Text(student.fullName.isEmpty ? student.email : student.fullName),
      subtitle: Text(
        '${student.email}\n'
        '${hasPhone ? 'Phone registered' : 'No phone registered yet'}',
      ),
      isThreeLine: true,
      trailing: TextButton(
        // Nothing to reset if no phone is registered.
        onPressed: hasPhone ? () => _reset(student) : null,
        child: const Text('Reset Device'),
      ),
    );
  }
}
