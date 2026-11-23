import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/date_format.dart';
import '../../core/rpc_error.dart';
import '../../models/live_attendee.dart';
import '../../services/live_attendance_service.dart';

// The "Present" list shown under the QR on the session screen.
// Header: "Present X / Y enrolled" (Y = students enrolled in the course).
// It loads once, then reloads by itself every time Realtime
// reports a change in this session's attendance.
class LiveAttendanceList extends StatefulWidget {
  final String sessionId;
  final String courseId;
  const LiveAttendanceList({
    super.key,
    required this.sessionId,
    required this.courseId,
  });

  @override
  State<LiveAttendanceList> createState() => _LiveAttendanceListState();
}

class _LiveAttendanceListState extends State<LiveAttendanceList> {
  final _service = LiveAttendanceService();

  RealtimeChannel? _channel;
  List<LiveAttendee> _present = [];
  int? _enrolled; // null until loaded
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _service.listen(widget.sessionId, _load);
  }

  @override
  void dispose() {
    // Stop listening when the screen closes.
    if (_channel != null) _service.stopListening(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _service.getPresent(widget.sessionId);
      final enrolled = await _service.countEnrolled(widget.courseId);
      if (!mounted) return;
      setState(() {
        _present = list;
        _enrolled = enrolled;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: "Present 3 / 25 enrolled" + manual refresh button
        Row(
          children: [
            Text(
              _enrolled == null
                  ? 'Present ${_present.length}'
                  : 'Present ${_present.length} / $_enrolled enrolled',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
        ),
        const Divider(),
        _buildContent(),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Could not load the list: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (_present.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('No students marked yet.')),
      );
    }

    // A plain Column (not a ListView) because the session screen
    // already scrolls.
    return Column(
      children: [
        for (final student in _present)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.check, color: Colors.white),
            ),
            title: Text(student.fullName),
            subtitle: Text(student.email),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatTime(student.markedAt)),
                Text(
                  student.method == 'manual' ? 'Manual' : 'QR',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
