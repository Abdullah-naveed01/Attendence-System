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
import '../../widgets/alerts_button.dart';
import '../../widgets/today_class_card.dart';
import 'session_screen.dart';
import 'students_screen.dart';

// Teacher Home:
// - "Today's Classes" from the timetable at the top
// - the teacher's own courses with their weekly schedule below
// "Start Class" is enabled only on the right day, from start_time to
// end_time (Pakistan time). The server checks the same rule in start_session.
class TeacherHome extends StatefulWidget {
  final Profile profile;
  const TeacherHome({super.key, required this.profile});

  @override
  State<TeacherHome> createState() => _TeacherHomeState();
}

class _TeacherHomeState extends State<TeacherHome> {
  final _courseService = CourseService();
  final _timetableService = TimetableService();

  bool _loading = true;
  String? _error;
  List<Course> _courses = [];
  List<TimetableSlot> _slots = []; // this teacher's whole week

  // Re-check the clock every minute so buttons open and close on time.
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final courses = await _courseService.getTeacherCourses(widget.profile.id);
      final slots = await _timetableService.getMySlots();
      if (!mounted) return;
      setState(() {
        _courses = courses;
        // Keep only slots of this teacher's own courses.
        _slots = slots
            .where((s) => s.course.teacherId == widget.profile.id)
            .toList();
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

  // Slots of one course.
  List<TimetableSlot> _slotsOf(Course course) =>
      _slots.where((s) => s.course.id == course.id).toList();

  // A course can start if one of its slots is open right now.
  bool _canStart(Course course, DateTime now) =>
      _slotsOf(course).any((s) => s.canStartAt(now));

  Future<void> _startClass(Course course) async {
    // When the session screen closes it returns a message (e.g. "Class ended").
    final message = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => SessionScreen(course: course)),
    );

    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // "Start Class" button + a small line under it ("Opens Monday 08:30").
  Widget _startButton(Course course, DateTime now) {
    final canStart = _canStart(course, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Class'),
          // null = disabled
          onPressed: canStart ? () => _startClass(course) : null,
        ),
        const SizedBox(height: 4),
        Text(
          canStart ? 'Open now' : opensText(_slotsOf(course), now),
          style: TextStyle(
            fontSize: 12,
            color: canStart ? Colors.green : Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Courses'),
        actions: [
          const AlertsButton(),
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'My Students',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const StudentsScreen(title: 'My Students'),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 1) Loading
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2) Error
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final now = pakistanNow();
    final today = slotsForToday(_slots, now);

    // 3) Today's classes + all courses (pull down to refresh)
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            "Today's Classes - ${dayName(now.weekday)}",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Pakistan time ${formatClock24(now.hour * 60 + now.minute)}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (today.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No classes scheduled today.'),
              ),
            ),
          ...today.map(
            (slot) => TodayClassCard(
              slot: slot,
              now: now,
              action: _startButton(slot.course, now),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'My Courses',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_courses.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No courses are assigned to you yet.'),
              ),
            ),
          ..._courses.map((course) => _buildCourseCard(course, now)),
        ],
      ),
    );
  }

  // One course: name, code, weekly schedule, Start Class.
  Widget _buildCourseCard(Course course, DateTime now) {
    final slots = _slotsOf(course);

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
                    course.name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text('${course.code}  •  ${course.semester}'),
                  const SizedBox(height: 8),
                  // Weekly schedule, e.g. "Mon 08:30 - 11:30"
                  if (slots.isEmpty)
                    const Text('No timetable slots',
                        style: TextStyle(color: Colors.grey)),
                  ...slots.map(
                    (slot) => Row(
                      children: [
                        const Icon(Icons.schedule,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(slot.dayAndTime),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _startButton(course, now),
          ],
        ),
      ),
    );
  }
}
