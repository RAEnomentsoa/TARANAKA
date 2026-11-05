import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/security/pin_crypto.dart';
import 'package:taranaka/core/security/pin_lockout.dart';

void main() {
  final crypto = PinCrypto();
  final device = List<int>.generate(32, (i) => i);
  final salt = List<int>.generate(16, (i) => 100 + i);

  test('the right PIN unwraps the master key, a wrong one does not', () {
    final master = crypto.randomBytes();
    final wrapped = crypto.wrap(device, salt, '1234', master);
    expect(wrapped, isNot(master));
    expect(crypto.unwrap(device, salt, '1234', wrapped), master);
    expect(crypto.unwrap(device, salt, '1235', wrapped), isNot(master));
  });

  test('the device secret is needed: same PIN on another phone gives another key', () {
    final master = crypto.randomBytes();
    final wrapped = crypto.wrap(device, salt, '1234', master);
    final otherDevice = List<int>.generate(32, (i) => 255 - i);
    expect(crypto.unwrap(otherDevice, salt, '1234', wrapped), isNot(master));
  });

  test('verifier tells a wrong PIN', () {
    final v = crypto.verifier(device, salt, '0000');
    expect(PinCrypto.sameBytes(v, crypto.verifier(device, salt, '0000')), isTrue);
    expect(PinCrypto.sameBytes(v, crypto.verifier(device, salt, '0001')), isFalse);
  });

  test('PIN format is 4 digits', () {
    expect(PinCrypto.isValidPin('0420'), isTrue);
    for (final bad in ['123', '12345', '12a4', '']) {
      expect(PinCrypto.isValidPin(bad), isFalse, reason: bad);
    }
  });

  test('recovery answers ignore case and spaces', () {
    expect(PinCrypto.normaliseAnswer('  Ambohi   Tsoa '), 'ambohi tsoa');
  });

  test('passphrase is 64 hex characters', () {
    expect(PinCrypto.passphrase(crypto.randomBytes()), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  group('progressive delay (spec §8: 5 wrong PINs)', () {
    const policy = PinLockoutPolicy();
    test('no delay for the first 4 failures', () {
      for (var i = 1; i <= 4; i++) {
        expect(policy.delayAfter(i), Duration.zero);
      }
    });
    test('grows from the 5th failure and caps at 15 min', () {
      expect(policy.delayAfter(5), const Duration(seconds: 30));
      expect(policy.delayAfter(6), const Duration(minutes: 1));
      expect(policy.delayAfter(7), const Duration(minutes: 5));
      expect(policy.delayAfter(8), const Duration(minutes: 15));
      expect(policy.delayAfter(30), const Duration(minutes: 15));
    });
  });
}
