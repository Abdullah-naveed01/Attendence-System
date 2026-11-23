import 'package:local_auth/local_auth.dart';

// The result of asking the user to verify with fingerprint / face / PIN.
enum VerifyResult {
  verified, // the user passed the check
  noLockOnPhone, // the phone has no fingerprint and no PIN set -> we continue
  failed, // the user cancelled or failed the check
}

// Asks the phone owner to prove it's them before scanning.
// This only protects the phone locally; the real attendance checks
// (QR, enrollment, device) still happen on the server.
class BiometricService {
  final _auth = LocalAuthentication();

  // Also returns a message when the check fails, to show on screen.
  Future<(VerifyResult, String?)> verify() async {
    try {
      // false = no fingerprint/face AND no PIN/pattern/password on this phone.
      final supported = await _auth.isDeviceSupported();
      if (!supported) return (VerifyResult.noLockOnPhone, null);

      final ok = await _auth.authenticate(
        localizedReason: 'Verify it is you to mark attendance',
        // false = fingerprint OR the phone's PIN/pattern is accepted.
        biometricOnly: false,
      );
      if (ok) return (VerifyResult.verified, null);
      return (VerifyResult.failed, 'Verification failed. Please try again.');
    } on LocalAuthException catch (e) {
      switch (e.code) {
        // Nothing is set up on this phone -> continue without the check.
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
          return (VerifyResult.noLockOnPhone, null);

        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
          return (VerifyResult.failed, 'Verification was cancelled.');

        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          return (
            VerifyResult.failed,
            'Too many attempts. Unlock your phone with your PIN, then try again.'
          );

        default:
          return (VerifyResult.failed, 'Verification error: ${e.code.name}');
      }
    }
  }
}
