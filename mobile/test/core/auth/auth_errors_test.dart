import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/auth/auth_service.dart';

void main() {
  test('Firebase Auth codes the screens can explain (no generic error)', () {
    expect(FirebaseAuthService.authErrorOf('network-request-failed'), AuthError.offline);
    expect(FirebaseAuthService.authErrorOf('email-already-in-use'), AuthError.emailInUse);
    expect(FirebaseAuthService.authErrorOf('operation-not-allowed'), AuthError.notConfigured);
    expect(FirebaseAuthService.authErrorOf('admin-restricted-operation'), AuthError.notConfigured);
    // Provider off: Android says "internal-error" with the reason in the message.
    expect(
      FirebaseAuthService.authErrorOf(
        'internal-error',
        'An internal error has occurred. [ CONFIGURATION_NOT_FOUND ]',
      ),
      AuthError.notConfigured,
    );
    expect(
      FirebaseAuthService.authErrorOf('unknown', 'A network error (such as timeout) occurred'),
      AuthError.offline,
    );
    expect(FirebaseAuthService.authErrorOf('internal-error', 'something else'), AuthError.unknown);
  });

  test('Firestore codes', () {
    expect(FirebaseAuthService.firestoreErrorOf('unavailable'), AuthError.offline);
    expect(FirebaseAuthService.firestoreErrorOf('permission-denied'), AuthError.notConfigured);
    expect(FirebaseAuthService.firestoreErrorOf('not-found'), AuthError.notConfigured);
  });
}
