import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/rpc_error.dart';
import '../../models/marked_class.dart';
import '../../services/attendance_service.dart';
import '../../services/biometric_service.dart';
import '../../services/device_service.dart';
import 'scan_result_screen.dart';

// The steps this screen goes through, in order.
enum _Step {
  verifying, // asking for fingerprint / PIN
  verifyFailed, // the user cancelled or failed -> show "Try again"
  scanning, // camera is on, waiting for a QR
  submitting, // QR found, sending it to the server
}

// Scan screen:
// 1) verify the user with fingerprint / PIN (skipped if the phone has no lock)
// 2) scan the teacher's QR with the camera (stops after the first QR)
// 3) send the QR token + Android ID to mark_attendance
// 4) show the result screen
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final _biometricService = BiometricService();
  final _deviceService = DeviceService();
  final _attendanceService = AttendanceService();

  // Only look for QR codes (faster, ignores other barcodes).
  final _scannerController = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  _Step _step = _Step.verifying;
  String? _verifyError;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  // ---------- Step 1: fingerprint / PIN ----------
  Future<void> _verify() async {
    setState(() {
      _step = _Step.verifying;
      _verifyError = null;
    });

    final (result, message) = await _biometricService.verify();
    if (!mounted) return;

    if (result == VerifyResult.failed) {
      setState(() {
        _step = _Step.verifyFailed;
        _verifyError = message;
      });
      return;
    }

    if (result == VerifyResult.noLockOnPhone) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No fingerprint or PIN set on this phone. Continuing.'),
      ));
    }
    setState(() => _step = _Step.scanning);
  }

  // ---------- Step 2 + 3: QR found -> send to server ----------
  Future<void> _onDetect(BarcodeCapture capture) async {
    // Only handle the FIRST QR; ignore the rest while we are busy.
    if (_step != _Step.scanning) return;

    String? token;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        token = barcode.rawValue;
        break;
      }
    }
    if (token == null) return;

    setState(() => _step = _Step.submitting);
    await _scannerController.stop();

    MarkResult? result;
    MarkedClass? markedClass; // which class it was marked for (if MARKED)
    String? errorMessage;
    try {
      final deviceId = await _deviceService.getAndroidId();
      result = await _attendanceService.markAttendance(token.trim(), deviceId);
      if (result.isMarked) {
        markedClass = await _attendanceService.getMyLastAttendance();
      }
    } catch (e) {
      errorMessage = friendlyError(e);
    }
    if (!mounted) return;

    // ---------- Step 4: show the result ----------
    final scanAgain = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanResultScreen(
          code: result?.code,
          data: result?.data ?? const {},
          markedClass: markedClass,
          errorMessage: errorMessage,
        ),
      ),
    );
    if (!mounted) return;

    if (scanAgain == true) {
      setState(() => _step = _Step.scanning);
      await _scannerController.start();
    } else {
      Navigator.pop(context); // back to Student Home
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: switch (_step) {
        _Step.verifying => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fingerprint, size: 72),
                SizedBox(height: 12),
                Text('Verify it is you...'),
              ],
            ),
          ),
        _Step.verifyFailed => _buildVerifyFailed(),
        _Step.scanning || _Step.submitting => _buildScanner(),
      },
    );
  }

  Widget _buildVerifyFailed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 72, color: Colors.orange),
            const SizedBox(height: 12),
            Text(
              _verifyError ?? 'Verification failed.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.fingerprint),
              label: const Text('Try Again'),
              onPressed: _verify,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
          errorBuilder: _buildCameraError,
        ),

        // Hint at the bottom
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              "Point the camera at the QR code on the teacher's screen",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),

        // While sending to the server
        if (_step == _Step.submitting)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Marking attendance...',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Shown instead of the camera if it cannot start (e.g. permission denied).
  Widget _buildCameraError(BuildContext context, MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 72, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              denied ? 'Camera permission is needed' : 'Camera could not start',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'To scan the QR code, allow camera access:\n'
                      'Settings > Apps > Smart Attendance > Permissions > Camera > Allow.\n'
                      'Then come back and tap Try Again.'
                  : (error.errorDetails?.message ?? error.errorCode.name),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (denied)
              OutlinedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
                onPressed: _deviceService.openAppSettings,
              ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              onPressed: () => _scannerController.start(),
            ),
          ],
        ),
      ),
    );
  }
}
