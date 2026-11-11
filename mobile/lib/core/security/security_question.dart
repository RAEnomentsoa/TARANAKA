import 'pin_crypto.dart';

/// Rules of the secret question, written by the user herself at the profile
/// creation (offline recovery of the secret code). The profile keeps the
/// question as typed (ProfileInfo.recoveryQuestion); the answer is never
/// kept, only a verifier of it (see ProfileRegistry).
abstract final class SecurityQuestion {
  /// Shortest question accepted (after removing spaces at the ends).
  static const minQuestionLength = 3;

  /// Shortest answer accepted.
  static const minAnswerLength = 2;

  static const maxQuestionLength = 120;
  static const maxAnswerLength = 60;

  static bool validQuestion(String question) => question.trim().length >= minQuestionLength;

  /// The answer is compared without capitals nor extra spaces, as at the
  /// recovery ([PinCrypto.normaliseAnswer]).
  static bool validAnswer(String answer) => PinCrypto.normaliseAnswer(answer).length >= minAnswerLength;
}
