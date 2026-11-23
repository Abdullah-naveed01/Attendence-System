import 'package:flutter/material.dart';

import '../../core/rpc_error.dart';
import '../../models/course.dart';
import '../../models/course_attendance.dart';
import '../../services/attendance_service.dart';
import 'history_screen.dart';

// My Attendance: one card per course with
// percentage = attended classes / total classes x 100.
// A red warning appears when a course is below 75%.
class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({super.key});

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  final _attendanceService = AttendanceService();

  bool _loading = true;
  String? _error;
  List<CourseAttendance> _items = [];

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
      final items = await _attendanceService.getMySummary();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  void _openHistory(CourseAttendance item) {
    final course = Course(
      id: item.courseId,
      name: item.courseName,
      code: item.courseCode,
      semester: '',
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HistoryScreen(initialCourse: course)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance')),
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

    if (_items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.menu_book, size: 60, color: Colors.grey),
          SizedBox(height: 12),
          Text('You are not enrolled in any course yet.',
              textAlign: TextAlign.center),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (context, index) => _buildCourseCard(_items[index]),
    );
  }

  Widget _buildCourseCard(CourseAttendance item) {
    final low = item.isBelowMinimum;
    final color = !item.hasClasses
        ? Colors.grey
        : (low ? Colors.red : Colors.green);

    return Card(
      // Light red background for courses below 75%
      color: low ? Colors.red.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: low
            ? const BorderSide(color: Colors.red, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openHistory(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Course name + big percentage
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.courseName,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(item.courseCode),
                      ],
                    ),
                  ),
                  Text(
                    item.hasClasses
                        ? '${item.percentage.toStringAsFixed(0)}%'
                        : '--',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: item.percentage / 100,
                minHeight: 8,
                color: color,
                backgroundColor: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                item.hasClasses
                    ? 'Attended ${item.attendedSessions} of ${item.totalSessions} classes'
                    : 'No classes held yet',
              ),

              // Warning below 75%
              if (low) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Below 75%! Attend the next '
                          '${item.classesNeededFor75} '
                          'class${item.classesNeededFor75 == 1 ? '' : 'es'} '
                          'in a row to reach 75%.',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('Tap for history ›',
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
