import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/growth/who_lms.dart';

/// WHO reference cases: LMS rows of the WHO 2006 tables and the SD values WHO
/// publishes in its simplified z-score tables (kg, rounded to 0.1). Same rows
/// as the server tests (Backend_serveur/nutrition/tests_classification.py).
const boyLength75 = (
  lms: Lms(-0.3521, 9.5032, 0.08295),
  sd: {-3: 7.5, -2: 8.1, -1: 8.8, 0: 9.5, 1: 10.3, 2: 11.3, 3: 12.3},
);
const girlHeight80 = (
  lms: Lms(-0.3833, 10.2332, 0.08932),
  sd: {-3: 7.9, -2: 8.6, -1: 9.4, 0: 10.2, 1: 11.2, 2: 12.3, 3: 13.6},
);
const boyWeightAge18Months = (
  lms: Lms(0.0211, 10.9385, 0.11119),
  sd: {-3: 7.8, -2: 8.8, -1: 9.8, 0: 10.9, 1: 12.2, 2: 13.7, 3: 15.3},
);

void main() {
  test('the SD values published by WHO are found from the LMS rows', () {
    for (final (name, table) in [
      ('boy W/L 75 cm', boyLength75),
      ('girl W/H 80 cm', girlHeight80),
      ('boy W/A 18 months', boyWeightAge18Months),
    ]) {
      for (final MapEntry(key: k, value: published) in table.sd.entries) {
        final lms = table.lms;
        expect(
          WhoLms.valueAt(lms.l, lms.m, lms.s, k.toDouble()),
          closeTo(published, 0.05 + 1e-9),
          reason: '$name at $k SD',
        );
      }
    }
  });

  test('the median weight gives z = 0', () {
    const lms = Lms(-0.3521, 9.5032, 0.08295);
    expect(WhoLms.zscore(lms.m, lms.l, lms.m, lms.s, restricted: true), closeTo(0, 1e-6));
  });

  test('published weights give back their SD (±0.15, they are rounded)', () {
    final lms = boyLength75.lms;
    for (final MapEntry(key: k, value: published) in boyLength75.sd.entries) {
      expect(WhoLms.zscore(published, lms.l, lms.m, lms.s, restricted: true), closeTo(k, 0.15));
    }
  });

  test("WHO's restricted method beyond -3 SD", () {
    final lms = boyLength75.lms;
    final sd3 = WhoLms.valueAt(lms.l, lms.m, lms.s, -3);
    final sd2 = WhoLms.valueAt(lms.l, lms.m, lms.s, -2);
    final weight = sd3 - 0.5 * (sd2 - sd3);
    expect(WhoLms.zscore(weight, lms.l, lms.m, lms.s, restricted: true), closeTo(-3.5, 1e-6));
    expect(WhoLms.zscore(weight, lms.l, lms.m, lms.s), isNot(closeTo(-3.5, 0.01)));
  });

  test("WHO's restricted method beyond +3 SD", () {
    final lms = boyLength75.lms;
    final sd3 = WhoLms.valueAt(lms.l, lms.m, lms.s, 3);
    final sd2 = WhoLms.valueAt(lms.l, lms.m, lms.s, 2);
    final weight = sd3 + 1.0 * (sd3 - sd2);
    expect(WhoLms.zscore(weight, lms.l, lms.m, lms.s, restricted: true), closeTo(4, 1e-6));
  });

  test('L = 0 uses the log form', () {
    expect(WhoLms.zscore(math.e * 10, 0, 10, 0.5), closeTo(2, 1e-9));
  });

  test('rounding matches the server (Decimal ROUND_HALF_UP on str(z))', () {
    expect(WhoLms.round2(-3.005), -3.01);
    expect(WhoLms.round2(2.675), 2.68);
    expect(WhoLms.round2(-2.004), -2.0);
    expect(WhoLms.round2(-0.001), 0);
    expect(WhoLms.round2(1.2), 1.2);
  });

  group('table files (WHO anthro format)', () {
    // The three official rows above, written in the WHO file layout.
    const wfl = 'sex\tlength\tl\tm\ts\tlorh\n1\t75.0\t-0.3521\t9.5032\t0.08295\tL\n';
    const wfh = 'sex\theight\tl\tm\ts\tlorh\n2\t80.0\t-0.3833\t10.2332\t0.08932\tH\n';
    const wfa = 'sex\tage\tl\tm\ts\n1\t548\t0.0211\t10.9385\t0.11119\n';
    final tables = WhoTables.fromFiles({WhoIndicator.wfl: wfl, WhoIndicator.wfh: wfh, WhoIndicator.wfa: wfa});

    test('rows are found by sex and key', () {
      expect(tables.lookup(WhoIndicator.wfl, 'M', 75.0)!.m, 9.5032);
      expect(tables.lookup(WhoIndicator.wfh, 'F', 80)!.l, -0.3833);
      expect(tables.lookup(WhoIndicator.wfa, 'M', 548)!.s, 0.11119);
      expect(tables.lookup(WhoIndicator.wfl, 'F', 75.0), isNull);
      expect(tables.has(WhoIndicator.lhfa), isFalse);
    });

    test('weight-for-length before 731 days, weight-for-height after', () {
      final young = GrowthMath.compute(
        tables,
        sex: 'M',
        ageDays: 548,
        weightKg: 9.5032,
        correctedLengthCm: 75.0,
      );
      expect(young.whz, 0);
      expect(young.waz, isNotNull);
      expect(young.haz, isNull, reason: 'length-for-age table not loaded: never estimated');

      final girl = GrowthMath.compute(tables, sex: 'F', ageDays: 900, weightKg: 7.9, correctedLengthCm: 80.0);
      expect(girl.whz, closeTo(-3, 0.15));
    });

    test('outside the tables or the age range: no z-score', () {
      expect(
        GrowthMath.compute(tables, sex: 'M', ageDays: 548, weightKg: 9, correctedLengthCm: 44.9).whz,
        isNull,
      );
      expect(
        GrowthMath.compute(tables, sex: 'M', ageDays: 1900, weightKg: 9, correctedLengthCm: 75).any,
        isFalse,
      );
    });

    test('an unexpected header is refused', () {
      expect(() => WhoTables.parse(WhoIndicator.wfa, 'a\tb\n1\t2\n'), throwsFormatException);
    });
  });

  test('no WHO table is bundled yet: nothing is computed', () {
    final z = GrowthMath.compute(
      WhoTables.empty,
      sex: 'F',
      ageDays: 548,
      weightKg: 8.6,
      correctedLengthCm: 77.5,
    );
    expect(z.any, isFalse);
  });
}
