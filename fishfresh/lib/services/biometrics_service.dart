// lib/services/biometrics_service.dart
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricsService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isDeviceSupported() async {
    try { return await _auth.isDeviceSupported(); } catch (_) { return false; }
  }

  Future<bool> canCheckBiometrics() async {
    try { return await _auth.canCheckBiometrics; } catch (_) { return false; }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try { return await _auth.getAvailableBiometrics(); } catch (_) { return <BiometricType>[]; }
  }

  /// Returns (success, message). If success==false, message is a human-readable reason.
  Future<(bool, String?)> authenticate({bool allowDeviceCredential = false, String reason = 'Authenticate'}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: !allowDeviceCredential, // allow device PIN/pattern if false
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return (ok, ok ? null : 'Authentication failed or canceled');
    } on PlatformException catch (e) {
      // Common codes from local_auth on Android/iOS:
      // notAvailable, notEnrolled, passcodeNotSet, lockedOut, permanentlyLockedOut,
      // userCanceled, systemCancel, appCancel, otherOperatingSystem
      return (false, _explainPlatformException(e));
    } catch (e) {
      return (false, 'Unexpected error: $e');
    }
  }

  String _explainPlatformException(PlatformException e) {
    switch (e.code) {
      case 'NotAvailable':
      case 'notAvailable':
        return 'Biometrics not available on this device.';
      case 'NotEnrolled':
      case 'notEnrolled':
        return 'No Face ID/Fingerprint enrolled. Please add one in Settings.';
      case 'PasscodeNotSet':
      case 'passcodeNotSet':
        return 'Device screen lock is not set. Set a PIN/Pattern/Password first.';
      case 'LockedOut':
      case 'lockedOut':
        return 'Too many failed attempts. Try again later.';
      case 'PermanentlyLockedOut':
      case 'permanentlyLockedOut':
        return 'Biometrics permanently locked. Use device credentials.';
      case 'userCanceled':
        return 'You canceled the authentication.';
      case 'systemCancel':
        return 'System canceled the authentication.';
      default:
        return 'Authentication error: ${e.code} ${e.message ?? ''}'.trim();
    }
  }

  Future<void> stop() async { try { await _auth.stopAuthentication(); } catch (_) {} }
}
