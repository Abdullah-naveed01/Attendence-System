import 'package:flutter/material.dart';

import '../../core/rpc_error.dart';
import '../../models/course.dart';
import '../../models/teacher_summary.dart';
import '../../services/teacher_admin_service.dart';
import 'add_teacher_screen.dart';

// Admin: list of all teachers with the courses they teach.
// "Add Teacher" button, and a delete button on each teacher.
class TeachersScreen extends StatefulWidget {
  const TeachersScreen({super.key});

  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  final _service = TeacherAdminService();

  bool _loading = true;
  String? _error;
  List<Course> _courses = [];
  List<TeacherSummary> _teachers = [];
  String? _removingId; // teacher currently being removed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final courses = await _service.getAllCourses();
      final teachers = await _service.getTeachers(courses);
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _teachers = teachers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _openAddTeacher() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddTeacherScreen(allCourses: _courses, teachers: _teachers),
      ),
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Teacher added')));
      _load();
    }
  }

  Future<void> _confirmRemove(TeacherSummary teacher) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${teacher.displayName}?'),
        content: Text(
          'Their login account (${teacher.profile.email}) will be deleted.\n\n'
          'Their courses will stay, with all sessions and attendance, '
          'but will have no teacher until you assign a new one.\n\n'
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;

    setState(() => _removingId = teacher.profile.id);
    try {
      await _service.removeTeacher(teacher.profile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${teacher.displayName} removed')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teachers')),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.person_add),
              label: const Text('Add Teacher'),
              onPressed: _openAddTeacher,
            ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }

    if (_teachers.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Text('No teachers yet. Tap "Add Teacher".',
              textAlign: TextAlign.center),
        ],
      );
    }

    return ListView.builder(
      // extra space at the bottom so the button does not cover the last card
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: _teachers.length,
      itemBuilder: (context, index) => _buildTeacherCard(_teachers[index]),
    );
  }

  Widget _buildTeacherCard(TeacherSummary teacher) {
    final removing = _removingId == teacher.profile.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teacher.displayName,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(teacher.profile.email,
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  if (teacher.courses.isEmpty)
                    const Text('No courses assigned',
                        style: TextStyle(color: Colors.orange)),
                  ...teacher.courses.map(
                    (course) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${course.code}  ${course.name}'),
                    ),
                  ),
                ],
              ),
            ),
            removing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Remove teacher',
                    onPressed: _removingId == null
                        ? () => _confirmRemove(teacher)
                        : null,
                  ),
          ],
        ),
      ),
    );
  }
}
