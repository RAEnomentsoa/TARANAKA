import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Key handling for the encrypted profile databases (spec §8).
///
/// - Each profile has a random 256-bit **master key**: it is the SQLCipher key
///   of the profile's database.
/// - The master key is stored only **wrapped** by a key derived from the PIN
///   and from a device secret kept in the Android Keystore:
///   `pad = HMAC-SHA256(deviceSecret, "wrap" | salt | pin)`, `wrapped = master XOR pad`.
///   Without the Keystore secret, the 10 000 possible PINs can't be tried
///   offline against a copied file.
/// - A separate verifier `HMAC-SHA256(deviceSecret, "verify" | salt | pin)`
///   tells a wrong PIN without opening the database.
/// - Changing the PIN re-wraps the master key: the database is not re-encrypted.
/// - The optional recovery answer wraps the same master key a second time.
/// - The recovery codes (6 codes of 4 characters, given at the profile
///   creation, to download or write down) wrap it once each: any one of them
///   resets a forgotten PIN.
class PinCrypto {
  PinCrypto({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  static const int keyLength = 32;

  Uint8List randomBytes([int length = keyLength]) =>
      Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

  Uint8List _hmac(List<int> secret, String purpose, List<int> salt, String value) {
    final mac = Hmac(sha256, secret);
    final message = <int>[...utf8.encode('taranaka-$purpose-v1'), 0, ...salt, 0, ...utf8.encode(value)];
    return Uint8List.fromList(mac.convert(message).bytes);
  }

  Uint8List verifier(List<int> deviceSecret, List<int> salt, String pin) =>
      _hmac(deviceSecret, 'verify', salt, pin);

  Uint8List wrap(List<int> deviceSecret, List<int> salt, String secret, List<int> masterKey) =>
      _xor(masterKey, _hmac(deviceSecret, 'wrap', salt, secret));

  Uint8List unwrap(List<int> deviceSecret, List<int> salt, String secret, List<int> wrapped) =>
      _xor(wrapped, _hmac(deviceSecret, 'wrap', salt, secret));

  /// Recovery answers are compared case- and space-insensitively.
  static String normaliseAnswer(String answer) => answer.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Constant-time comparison.
  static bool sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// SQLCipher passphrase for a master key (hex, so it is plain ASCII).
  static String passphrase(List<int> masterKey) =>
      masterKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _xor(List<int> a, List<int> b) {
    assert(a.length == b.length);
    return Uint8List.fromList(List<int>.generate(a.length, (i) => a[i] ^ b[i]));
  }

  /// Characters of a recovery code: no 0/O nor 1/I/L, so it is read and typed
  /// back without confusion.
  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// Number of recovery codes and length of each one.
  static const recoveryCodeCount = 6;
  static const recoveryCodeLength = 4;

  /// New recovery codes: 6 distinct codes of 4 letters and digits, each one
  /// valid. Short to write down; guessing is stopped by the attempt limit
  /// (5 tries, then a wait) and needs the device secret of the Keystore.
  List<String> newRecoveryCodes() {
    final codes = <String>{};
    while (codes.length < recoveryCodeCount) {
      codes.add(
        [for (var i = 0; i < recoveryCodeLength; i++) _codeAlphabet[_random.nextInt(_codeAlphabet.length)]]
            .join(),
      );
    }
    return codes.toList();
  }

  /// The codes kept together as one text ("ABCD EFGH …"), as stored in the
  /// profile database and shown in Paramètres.
  static String joinRecoveryCodes(List<String> codes) => codes.join(' ');

  /// The codes of a stored text: 4-character groups, or an older
  /// 16-character code as one.
  static List<String> splitRecoveryCodes(String text) {
    final parts = text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    return parts.length > 1
        ? [for (final p in parts) normaliseRecoveryCode(p)]
        : [normaliseRecoveryCode(text)];
  }

  /// What a typed code may be: the code itself or, when several codes were
  /// pasted together, each group of 4.
  static List<String> typedRecoveryCodes(String typed) {
    final n = normaliseRecoveryCode(typed);
    return {
      n,
      if (n.length > recoveryCodeLength && n.length % recoveryCodeLength == 0)
        for (var i = 0; i < n.length; i += recoveryCodeLength) n.substring(i, i + recoveryCodeLength),
    }.toList();
  }

  /// A typed code compared without case, spaces, dashes nor other signs.
  static String normaliseRecoveryCode(String code) => code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// A plausible e-mail address (the account itself is checked by the server).
  static bool isValidEmail(String email) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(email.trim());

  /// A PIN is exactly 4 digits (spec §3).
  static bool isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);
}
