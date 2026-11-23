import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../core/pakistan_time.dart';
import '../../core/rpc_error.dart';
import '../../models/course.dart';
import '../../models/profile.dart';
import '../../models/timetable_slot.dart';
import '../../services/auth_service.dart';
import '../../services/course_service.dart';
import '../../services/timetable_service.dart';
import '../../widgets/today_class_card.dart';
import 'history_screen.dart';
import 'my_attendance_screen.dart';
import 'scan_qr_screen.dart';

// Student Home: a big "Scan QR" button, today's classes from the timetable,
// and the list of enrolled courses.
class StudentHome extends StatefulWidget {
  final Profile profile;
  const StudentHome({super.key, required this.profile});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  final _courseService = CourseService();
  final _timetableService = TimetableService();

  bool _loading = true;
  String? _error;
  List<Course> _courses = [];

  // Timetable is loaded separately, so a timetable problem
  // never hides the course list.
  List<TimetableSlot> _slots = [];
  String? _timetableError;

  // Re-check the clock every minute so "Now / Finished" stays correct.
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _loadCourses();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _loading = true;
      _error = null;
      _timetableError = null;
    });

    try {
      final courses = await _courseService.getStudentCourses(widget.profile.id);
      if (!mounted) return;
      setState(() => _courses = courses);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    }

    try {
      final slots = await _timetableService.getMySlots();
      if (!mounted) return;
      setState(() => _slots = slots);
    } catch (e) {
      if (!mounted) return;
      setState(() => _timetableError = friendlyError(e));
    }

    if (mounted) setState(() => _loading = false);
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.profile.fullName.isEmpty
        ? widget.profile.email
        : widget.profile.fullName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Courses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCourses,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Welcome, $name', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),

            // Big Scan QR button
            SizedBox(
              height: 72,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  textStyle: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                icon: const Icon(Icons.qr_code_scanner, size: 32),
                label: const Text('Scan QR'),
                onPressed: () => _open(const ScanQrScreen()),
              ),
            ),
            const SizedBox(height: 12),

            // My Attendance + History buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.pie_chart),
                    label: const Text('My Attendance'),
                    onPressed: () => _open(const MyAttendanceScreen()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('History'),
                    onPressed: () => _open(const HistoryScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              "Today's Classes - ${dayName(pakistanNow().weekday)}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._buildTodaySection(),
            const SizedBox(height: 24),

            const Text(
              'Enrolled Courses',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._buildCourseSection(),
          ],
        ),
      ),
    );
  }

  // Today's classes: loading / error / none / list
  List<Widget> _buildTodaySection() {
    if (_loading) return const [];

    if (_timetableError != null) {
      return [
        Text('Could not load the timetable: $_timetableError',
            style: const TextStyle(color: Colors.red)),
      ];
    }

    final now = pakistanNow(); // the timetable is in Pakistan time
    final today = slotsForToday(_slots, now);
    if (today.isEmpty) {
      return const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('No classes scheduled today.'),
          ),
        ),
      ];
    }

    return today.map((slot) => TodayClassCard(slot: slot, now: now)).toList();
  }

  // Loading / error / empty / list
  List<Widget> _buildCourseSection() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (_error != null) {
      return [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 8),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Center(
          child: ElevatedButton(
            onPressed: _loadCourses,
            child: const Text('Retry'),
          ),
        ),
      ];
    }

    if (_courses.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'You are not enrolled in any course yet.',
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }

    return _courses
        .map(
          (course) => Card(
            child: ListTile(
              leading: const Icon(Icons.menu_book),
              title: Text(course.name),
              subtitle: Text('${course.code}  •  Semester ${course.semester}'),
              trailing: const Icon(Icons.chevron_right),
              // Tap a course to see its attendance history.
              onTap: () => _open(HistoryScreen(initialCourse: course)),
            ),
          ),
        )
        .toList();
  }
}
