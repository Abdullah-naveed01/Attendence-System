package com.Abdullah.smart_attendance

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth (biometrics) needs a FragmentActivity,
// so we use FlutterFragmentActivity instead of FlutterActivity.
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // A small "channel" that lets the Dart code ask Android for two things.
        // Dart side: lib/services/device_service.dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smart_attendance/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The phone's Android ID (unique per phone + app signing key).
                    "getAndroidId" -> {
                        val id = Settings.Secure.getString(
                            contentResolver, Settings.Secure.ANDROID_ID
                        )
                        result.success(id)
                    }
                    // Opens this app's page in Android Settings
                    // (used when camera permission was denied).
                    "openAppSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null)
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
