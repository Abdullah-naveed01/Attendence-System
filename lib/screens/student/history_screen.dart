import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../core/rpc_error.dart';
import '../../core/supabase_client.dart';
import '../../models/course.dart';
import '../../models/session_record.dart';
import '../../services/attendance_service.dart';
import '../../services/course_service.dart';

// History: pick a course, then see every class of that course
// (newest first) marked Present, Absent, or In progress.
class HistoryScreen extends StatefulWidget {
  // Optional: open with this course already selected.
  final Course? initialCourse;
  const HistoryScreen({super.key, this.initialCourse});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _courseService = CourseService();
  final _attendanceService = AttendanceService();

  List<Course> _courses = [];
  String? _selectedCourseId;
  bool _loadingCourses = true;

  List<SessionRecord> _records = [];
  bool _loadingRecords = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedCourseId = widget.initialCourse?.id;
    _loadCourses();
  }

  // Fill the course dropdown with the student's enrolled courses.
  Future<void> _loadCourses() async {
    setState(() {
      _loadingCourses = true;
      _error = null;
    });

    try {
      final userId = supabase.auth.currentUser!.id;
      final courses = await _courseService.getStudentCourses(userId);
      if (!mounted) return;

      setState(() {
        _courses = courses;
        _loadingCourses = false;
        // No course chosen yet -> pick the first one.
        if (_selectedCourseId == null && courses.isNotEmpty) {
          _selectedCourseId = courses.first.id;
        }
      });
      if (_selectedCourseId != null) _loadRecords();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loadingCourses = false;
      });
    }
  }

  // Load the classes of the selected course.
  Future<void> _loadRecords() async {
    final courseId = _selectedCourseId;
    if (courseId == null) return;

    setState(() {
      _loadingRecords = true;
      _error = null;
    });

    try {
      final records = await _attendanceService.getMyHistory(courseId);
      // Ignore the answer if the student switched course meanwhile.
      if (!mounted || courseId != _selectedCourseId) return;
      setState(() {
        _records = records;
        _loadingRecords = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loadingRecords = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance History')),
      body: _loadingCourses
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCourseId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Course',
                      border: OutlineInputBorder(),
                    ),
                    items: _courses
                        .map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.code}  ${c.name}',
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (id) {
                      setState(() {
                        _selectedCourseId = id;
                        _records = [];
                      });
                      _loadRecords();
                    },
                  ),
                ),
                if (!_loadingRecords && _error == null && _records.isNotEmpty)
                  _buildCounts(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadRecords,
                    child: _buildList(),
                  ),
                ),
              ],
            ),
    );
  }

  // "Present 5 • Absent 2"
  Widget _buildCounts() {
    final present = _records.where((r) => r.present).length;
    final absent = _records.where((r) => !r.present && !r.isActive).length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Chip(
            label: Text('Present $present'),
            backgroundColor: Colors.green.shade100,
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text('Absent $absent'),
            backgroundColor: Colors.red.shade100,
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loadingRecords) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton(
              onPressed: _courses.isEmpty ? _loadCourses : _loadRecords,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (_courses.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Text('You are not enrolled in any course yet.',
              textAlign: TextAlign.center),
        ],
      );
    }

    if (_records.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.event_busy, size: 60, color: Colors.grey),
          SizedBox(height: 12),
          Text('No classes held for this course yet.',
              textAlign: TextAlign.center),
        ],
      );
    }

    return ListView.separated(
      itemCount: _records.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildRow(_records[index]),
    );
  }

  Widget _buildRow(SessionRecord record) {
    // Present (green) / In progress (grey) / Absent (red)
    final String status;
    final Color color;
    final IconData icon;
    if (record.present) {
      status = 'Present';
      color = Colors.green;
      icon = Icons.check_circle;
    } else if (record.isActive) {
      status = 'In progress';
      color = Colors.grey;
      icon = Icons.schedule;
    } else {
      status = 'Absent';
      color = Colors.red;
      icon = Icons.cancel;
    }

    var subtitle = 'Class started ${formatTime(record.startedAt)}';
    if (record.present && record.markedAt != null) {
      subtitle = 'Marked at ${formatTime(record.markedAt!)}'
          '${record.method == 'manual' ? ' (by teacher)' : ''}';
    }

    return ListTile(
      leading: Icon(icon, color: color, size: 32),
      title: Text(formatDate(record.startedAt)),
      subtitle: Text(subtitle),
      trailing: Text(
        status,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
