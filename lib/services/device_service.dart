import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

// Everything about "this phone".
//
// Android ID: device_info_plus no longer provides it (removed in v4), so we
// read it with a tiny native channel in MainActivity.kt. The Android ID is
// unique per phone, which is what the server uses to bind a student to ONE phone.
class DeviceService {
  static const _channel = MethodChannel('smart_attendance/device');

  // Returns the Android ID, or null if it could not be read.
  // (If it is null, the server answers NO_DEVICE_ID.)
  Future<String?> getAndroidId() async {
    try {
      final id = await _channel.invokeMethod<String>('getAndroidId');
      if (id == null || id.isEmpty) return null;
      return id;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null; // e.g. not running on Android
    }
  }

  // A readable phone name like "Samsung SM-A515F" (only for display).
  Future<String> getPhoneName() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer} ${info.model}';
    } catch (_) {
      return 'Unknown phone';
    }
  }

  // Opens this app's page in Android Settings (to allow the camera).
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (_) {
      // Nothing else we can do; the screen already explains the steps.
    }
  }
}
