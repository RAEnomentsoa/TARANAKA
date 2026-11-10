/// Progressive delay after wrong PINs (spec §8: "5 PIN erronés → délai progressif").
///
/// This is a security rule, not a clinical one, so it lives in code.
/// Attempts 1–4: no delay. From the 5th failure: 30 s, 1 min, 5 min, then 15 min
/// for every further failure.
class PinLockoutPolicy {
  const PinLockoutPolicy();

  static const int freeAttempts = 4;
  static const List<Duration> delays = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// Delay imposed right after the [failures]-th consecutive failure.
  Duration delayAfter(int failures) {
    if (failures <= freeAttempts) return Duration.zero;
    final index = failures - freeAttempts - 1;
    return delays[index < delays.length ? index : delays.length - 1];
  }
}
