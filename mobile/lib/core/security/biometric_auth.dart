import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Unlock with the fingerprint (or the phone's other strong biometrics).
/// The PIN always stays possible.
abstract interface class BiometricAuth {
  /// True when the phone has a fingerprint sensor with a finger enrolled.
  Future<bool> available();

  /// Shows the system fingerprint dialog; true when it is confirmed.
  Future<bool> authenticate(String reason);
}

class LocalBiometricAuth implements BiometricAuth {
  LocalBiometricAuth([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> available() async {
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// No biometrics (tests, phones without sensor), or a fake answer in tests.
class NoBiometricAuth implements BiometricAuth {
  const NoBiometricAuth({this.isAvailable = false, this.confirm = false});

  final bool isAvailable;
  final bool confirm;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<bool> authenticate(String reason) async => isAvailable && confirm;
}
