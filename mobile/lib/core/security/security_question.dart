import 'pin_crypto.dart';

/// The predefined secret questions offered at the profile creation (offline
/// recovery of the secret code). The profile keeps only [stored]: the
/// question is shown in the language of the moment. Older profiles may hold a
/// question written by hand: it is shown as it is.
enum SecurityQuestion {
  firstPet,
  birthPlace,
  primarySchool,
  childhoodNickname,
  childhoodFriend,
  favouriteDish;

  static const _prefix = 'preset:';

  /// What the profile keeps (never the answer).
  String get stored => '$_prefix$name';

  /// The predefined question kept by a profile, null for a question written
  /// by hand (older profiles) or none.
  static SecurityQuestion? parse(String? stored) {
    if (stored == null || !stored.startsWith(_prefix)) return null;
    final id = stored.substring(_prefix.length);
    for (final q in values) {
      if (q.name == id) return q;
    }
    return null;
  }

  /// Shortest answer accepted (after removing spaces at the ends).
  static const minAnswerLength = 2;

  /// The answer is compared without capitals nor extra spaces, as at the
  /// recovery ([PinCrypto.normaliseAnswer]).
  static bool sameAnswer(String a, String b) => PinCrypto.normaliseAnswer(a) == PinCrypto.normaliseAnswer(b);

  static bool validAnswer(String answer) => PinCrypto.normaliseAnswer(answer).length >= minAnswerLength;
}
