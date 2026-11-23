import 'package:flutter/material.dart';

import '../../core/rpc_error.dart';
import '../../core/validators.dart';
import '../../models/course.dart';
import '../../services/admin_student_service.dart';
import '../../widgets/message_view.dart';

// Admin: "Add Student" form.
// All students are in the same class, so the new student is enrolled in
// every course that appears in the timetable. The form shows that list
// before saving. Pops with `true` when the student was created.
class AddStudentScreen extends StatefulWidget {
  const AddStudentScreen({super.key});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _service = AdminStudentService();

  bool _showPassword = false;

  // The class courses the student will be enrolled in
  List<Course> _classCourses = [];
  bool _loadingCourses = true;
  String? _coursesError;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClassCourses();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _loadClassCourses() async {
    setState(() {
      _loadingCourses = true;
      _coursesError = null;
    });
    try {
      final courses = await _service.getClassCourses();
      if (!mounted) return;
      setState(() {
        _classCourses = courses;
        _loadingCourses = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _coursesError = friendlyError(e);
        _loadingCourses = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.addStudent(
        fullName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
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
    final canSave =
        !_saving && !_loadingCourses && _coursesError == null && _classCourses.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Student')),
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

            // ---------- The courses that will be assigned ----------
            const Text(
              'Will be enrolled in (all class courses)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._buildCourseList(),
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
                label: const Text('Create Student'),
                onPressed: canSave ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Loading / error / empty / list of class courses
  List<Widget> _buildCourseList() {
    if (_loadingCourses) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_coursesError != null) {
      return [MessageView.error(_coursesError!, onRetry: _loadClassCourses)];
    }
    if (_classCourses.isEmpty) {
      return const [
        MessageView(
          icon: Icons.event_busy,
          message: 'The timetable has no courses yet, '
              'so a student cannot be added.',
        ),
      ];
    }
    return _classCourses
        .map(
          (course) => ListTile(
            dense: true,
            leading: const Icon(Icons.check, color: Colors.green),
            title: Text('${course.code}  ${course.name}'),
          ),
        )
        .toList();
  }
}
