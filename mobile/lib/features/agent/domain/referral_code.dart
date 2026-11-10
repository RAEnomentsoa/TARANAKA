import 'dart:math';

import '../../../core/security/secret_store.dart';

/// Unique referral code made offline (spec §7), short and easy to dictate:
/// `TRK-7F3K-9A02-W`.
///
/// - 6 random characters fixed for this install (30 bits), then a counter for
///   this install (never reused, even if a profile is deleted), then a check
///   character that catches most typing mistakes.
/// - Crockford base 32: no I, L, O, U, so nothing is confused with 1 or 0.
/// - The server refuses a code already used; the phone then draws a new install
///   prefix and makes a new code (see the sync service).
class ReferralCodeGenerator {
  ReferralCodeGenerator(this._store, {Random? random}) : _random = random ?? Random.secure();

  final SecretStore _store;
  final Random _random;

  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _prefixKey = 'referral_prefix_v1';
  static const _counterKey = 'referral_counter_v1';

  Future<String> next() async {
    var prefix = await _store.read(_prefixKey);
    if (prefix == null) {
      prefix = _randomPrefix();
      await _store.write(_prefixKey, prefix);
    }
    final counter = int.parse(await _store.read(_counterKey) ?? '0') + 1;
    await _store.write(_counterKey, '$counter');
    return format(prefix, counter);
  }

  /// After the server refused a code as already used.
  Future<void> rotatePrefix() => _store.write(_prefixKey, _randomPrefix());

  String _randomPrefix() => List.generate(6, (_) => alphabet[_random.nextInt(alphabet.length)]).join();

  static String encode(int value, {int minLength = 2}) {
    var v = value;
    final out = StringBuffer();
    do {
      out.write(alphabet[v % 32]);
      v ~/= 32;
    } while (v > 0);
    return out.toString().split('').reversed.join().padLeft(minLength, '0');
  }

  static String format(String prefix, int counter) {
    final body = '$prefix${encode(counter)}';
    return 'TRK-${body.substring(0, 4)}-${body.substring(4)}-${checkChar(body)}';
  }

  /// Position-weighted sum modulo 31 (prime), shown as one base-32 character.
  static String checkChar(String body) {
    var sum = 0;
    for (var i = 0; i < body.length; i++) {
      sum += (i + 1) * alphabet.indexOf(body[i]);
    }
    return alphabet[sum % 31];
  }

  /// Accepts what a person dictates or types: case, spaces, O/0 and I/L/1 mix-ups.
  static String? normalise(String input) {
    final s = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (!s.startsWith('TRK') || s.length < 3 + 6 + 2 + 1) return null;
    final body = s.substring(3, s.length - 1);
    if (body.split('').any((c) => !alphabet.contains(c))) return null;
    if (checkChar(body) != s[s.length - 1]) return null;
    return 'TRK-${body.substring(0, 4)}-${body.substring(4)}-${s[s.length - 1]}';
  }
}
