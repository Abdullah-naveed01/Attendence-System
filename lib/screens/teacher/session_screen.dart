import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/rpc_error.dart';
import '../../models/course.dart';
import '../../services/session_service.dart';
import 'live_attendance_list.dart';
import 'manual_attendance_screen.dart';

// The live class screen:
// - calls start_session as soon as it opens
// - shows a large QR code (containing only the qr_token)
// - gets a new QR from refresh_qr_token every 30 seconds
// - "End Class" calls end_session and returns to Home
// - below that, the live list of students marked present
class SessionScreen extends StatefulWidget {
  final Course course;
  const SessionScreen({super.key, required this.course});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  static const int refreshSeconds = 30;

  final _sessionService = SessionService();

  String? _sessionId; // null = the session has not started yet
  String? _qrToken;
  bool _resumed = false; // today's earlier class was reopened
  String? _startError; // set when start_session fails
  String? _refreshError; // set when a refresh fails (the old QR is still shown)

  Timer? _timer;
  int _secondsLeft = refreshSeconds;
  bool _refreshing = false;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    _startSession();
  }

  @override
  void dispose() {
    // Always stop the timer when the screen closes, or it keeps running.
    _timer?.cancel();
    super.dispose();
  }

  // ---------- Start ----------
  Future<void> _startSession() async {
    setState(() => _startError = null);

    try {
      final started = await _sessionService.startSession(widget.course.id);

      // If the teacher left the screen while it was loading,
      // end the session that was just created.
      if (!mounted) {
        _sessionService.endSession(started.sessionId);
        return;
      }

      setState(() {
        _sessionId = started.sessionId;
        _qrToken = started.qrToken;
        _resumed = started.resumed;
        _secondsLeft = refreshSeconds;
      });
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _startError = friendlyError(e));
    }
  }

  // ---------- 30-second refresh timer ----------
  void _startTimer() {
    _timer?.cancel();
    // Runs every second: counts down, and at zero requests a new QR.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_refreshing) return;

      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        _refreshQr();
      }
    });
  }

  Future<void> _refreshQr() async {
    _refreshing = true;
    setState(() => _secondsLeft = 0);

    try {
      final newToken = await _sessionService.refreshQrToken(_sessionId!);
      if (!mounted) return;
      setState(() {
        _qrToken = newToken;
        _refreshError = null;
        _secondsLeft = refreshSeconds;
      });
    } on RpcException catch (e) {
      if (!mounted) return;
      if (e.code == 'SESSION_NOT_ACTIVE') {
        // The class was already ended on the server -> go back to Home.
        _timer?.cancel();
        Navigator.pop(context, e.message);
        return;
      }
      _showRefreshFailed(e.message);
    } catch (e) {
      if (!mounted) return;
      _showRefreshFailed(friendlyError(e));
    } finally {
      _refreshing = false;
    }
  }

  // A refresh failed (e.g. no internet): show the error and retry in 5 seconds.
  void _showRefreshFailed(String message) {
    setState(() {
      _refreshError = message;
      _secondsLeft = 5;
    });
  }

  // ---------- End ----------
  Future<void> _confirmAndEnd() async {
    if (_ending) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this class?'),
        content:
            const Text('Students will no longer be able to mark attendance.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, End'),
          ),
        ],
      ),
    );

    if (yes != true || !mounted) return;

    setState(() => _ending = true);

    try {
      await _sessionService.endSession(_sessionId!);
      _timer?.cancel();
      if (!mounted) return;
      Navigator.pop(context, 'Class ended: ${widget.course.code}');
    } on RpcException catch (e) {
      if (!mounted) return;
      if (e.code == 'SESSION_NOT_ACTIVE') {
        // It was already ended — returning to Home is still correct.
        _timer?.cancel();
        Navigator.pop(context, e.message);
        return;
      }
      _showEndFailed(e.message);
    } catch (e) {
      if (!mounted) return;
      _showEndFailed(friendlyError(e));
    }
  }

  void _showEndFailed(String message) {
    setState(() => _ending = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not end class: $message')));
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    // While a session is running, the back button does not close the screen;
    // it asks "End this class?" first.
    return PopScope(
      canPop: _sessionId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmAndEnd();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.course.code)),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    // Starting failed
    if (_startError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 12),
              Text(_startError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _startSession,
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Still starting
    if (_sessionId == null || _qrToken == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Starting class...'),
          ],
        ),
      );
    }

    // Class is running: QR + countdown + End button
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            widget.course.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('Students: scan this QR code'),
          // Shown when today's earlier class was reopened
          if (_resumed) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 18, color: Colors.blue),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      "Resumed today's class - earlier attendance kept",
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // The QR contains only the qr_token, nothing else.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: _qrToken!,
              version: QrVersions.auto,
              size: 280,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Countdown
          LinearProgressIndicator(value: _secondsLeft / refreshSeconds),
          const SizedBox(height: 8),
          Text(
            _secondsLeft == 0
                ? 'Getting a new QR...'
                : 'New QR in $_secondsLeft seconds',
            style: const TextStyle(fontSize: 16),
          ),

          if (_refreshError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Could not refresh QR: $_refreshError',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: _ending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.stop),
              label: const Text('End Class'),
              onPressed: _ending ? null : _confirmAndEnd,
            ),
          ),

          // Mark a student without a phone (FR-23)
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Mark manually'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManualAttendanceScreen(
                    sessionId: _sessionId!,
                    course: widget.course,
                  ),
                ),
              ),
            ),
          ),

          // Live list of students who are marked present (Realtime).
          const SizedBox(height: 24),
          LiveAttendanceList(
            sessionId: _sessionId!,
            courseId: widget.course.id,
          ),
        ],
      ),
    );
  }
}
