import 'package:flutter/material.dart';

import '../../core/rpc_error.dart';
import '../../core/validators.dart';
import '../../models/course.dart';
import '../../models/teacher_summary.dart';
import '../../services/teacher_admin_service.dart';

// Admin: "Add Teacher" form.
// Full name, email, password, and one or more courses. Each course is either
// an existing course (picked from a list) or a new course (name, code, semester).
// Pops with `true` when the teacher was created.
class AddTeacherScreen extends StatefulWidget {
  final List<Course> allCourses;
  final List<TeacherSummary> teachers; // to show who teaches a course now

  const AddTeacherScreen({
    super.key,
    required this.allCourses,
    required this.teachers,
  });

  @override
  State<AddTeacherScreen> createState() => _AddTeacherScreenState();
}

class _AddTeacherScreenState extends State<AddTeacherScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _service = TeacherAdminService();

  bool _showPassword = false; // eye button: show / hide both passwords

  final List<Course> _pickedCourses = []; // existing courses
  final List<NewCourseInput> _newCourses = []; // courses to create

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // Who teaches this course right now (shown in the picker).
  String _currentTeacherOf(Course course) {
    if (course.teacherId == null) return 'No teacher';
    for (final t in widget.teachers) {
      if (t.profile.id == course.teacherId) return 'Now: ${t.displayName}';
    }
    return 'Has a teacher';
  }

  // ---------- Pick an existing course ----------
  Future<void> _pickExistingCourse() async {
    final available = widget.allCourses
        .where((c) => !_pickedCourses.any((p) => p.id == c.id))
        .toList();

    final picked = await showDialog<Course>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Pick a course'),
        children: available.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('All courses are already picked.'),
                ),
              ]
            : available
                .map(
                  (course) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, course),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${course.code}  ${course.name}'),
                      subtitle: Text(_currentTeacherOf(course)),
                    ),
                  ),
                )
                .toList(),
      ),
    );
    if (picked != null) setState(() => _pickedCourses.add(picked));
  }

  // ---------- Create a new course ----------
  Future<void> _addNewCourse() async {
    final course = await showDialog<NewCourseInput>(
      context: context,
      builder: (_) => _NewCourseDialog(
        takenCodes: {
          ...widget.allCourses.map((c) => normalizeCourseCode(c.code)),
          ..._newCourses.map((c) => c.code),
        },
      ),
    );
    if (course != null) setState(() => _newCourses.add(course));
  }

  // ---------- Save ----------
  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    final hasCourse = _pickedCourses.isNotEmpty || _newCourses.isNotEmpty;
    setState(() => _error = hasCourse ? null : 'Assign at least one course.');
    if (!formOk || !hasCourse) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.createTeacher(
        fullName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        existingCourseIds: _pickedCourses.map((c) => c.id).toList(),
        newCourses: _newCourses,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Teacher')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              validator: (v) => validateRequired(v, 'Full name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              validator: validateEmail,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password (at least 8 characters)',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                // Eye button: show or hide what was typed
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: validatePassword,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              obscureText: !_showPassword,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  validateConfirmPassword(v, _passwordController.text),
            ),
            const SizedBox(height: 24),

            // ---------- Courses ----------
            const Text(
              'Courses',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_pickedCourses.isEmpty && _newCourses.isEmpty)
              const Text('No courses yet.',
                  style: TextStyle(color: Colors.grey)),
            ..._pickedCourses.map(
              (course) => Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: Text('${course.code}  ${course.name}'),
                  subtitle: Text('Existing course - ${_currentTeacherOf(course)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove from list',
                    onPressed: () =>
                        setState(() => _pickedCourses.remove(course)),
                  ),
                ),
              ),
            ),
            ..._newCourses.map(
              (course) => Card(
                child: ListTile(
                  leading: const Icon(Icons.fiber_new, color: Colors.green),
                  title: Text('${course.code}  ${course.name}'),
                  subtitle: Text('New course - ${course.semester}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove from list',
                    onPressed: () => setState(() => _newCourses.remove(course)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Pick existing course'),
                  onPressed: _saving ? null : _pickExistingCourse,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Create new course'),
                  onPressed: _saving ? null : _addNewCourse,
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Create Teacher'),
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Small form in a dialog: course name, code, semester.
class _NewCourseDialog extends StatefulWidget {
  final Set<String> takenCodes; // codes that already exist (capital letters)
  const _NewCourseDialog({required this.takenCodes});

  @override
  State<_NewCourseDialog> createState() => _NewCourseDialogState();
}

class _NewCourseDialogState extends State<_NewCourseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _semester = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _semester.dispose();
    super.dispose();
  }

  void _add() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      NewCourseInput(
        name: _name.text.trim(),
        code: normalizeCourseCode(_code.text),
        semester: _semester.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New course'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Course name'),
              validator: (v) => validateRequired(v, 'Course name'),
            ),
            TextFormField(
              controller: _code,
              decoration:
                  const InputDecoration(labelText: 'Course code (e.g. CS-401)'),
              validator: (v) {
                final required = validateRequired(v, 'Course code');
                if (required != null) return required;
                if (widget.takenCodes.contains(normalizeCourseCode(v!))) {
                  return 'This course code already exists';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _semester,
              decoration:
                  const InputDecoration(labelText: 'Semester (e.g. Fall 2026)'),
              validator: (v) => validateRequired(v, 'Semester'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _add, child: const Text('Add')),
      ],
    );
  }
}
