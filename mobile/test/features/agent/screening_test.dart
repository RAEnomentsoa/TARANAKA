import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/growth/who_lms.dart';
import 'package:taranaka/core/security/secret_store.dart';
import 'package:taranaka/features/agent/domain/referral_code.dart';
import 'package:taranaka/features/agent/domain/screening.dart';

import '../../helpers/config_fixture.dart';

void main() {
  final config = sampleConfig();
  final today = DateTime(2026, 11, 4);

  ScreeningInput input({
    DateTime? birth,
    int? muac,
    String oedema = 'aucun',
    String position = 'couche',
    double weight = 8.6,
    double length = 77.5,
    List<String> signs = const [],
    bool complications = false,
    String appetite = 'non_teste',
    DateTime? on,
  }) => ScreeningInput(
    sex: 'F',
    birthDate: birth ?? DateTime(2025, 5, 4), // 18 months on 4 Nov 2026
    measureDate: on ?? today,
    weightKg: weight,
    lengthCm: length,
    position: position,
    muacMm: muac,
    oedema: oedema,
    dangerSigns: signs,
    complications: complications,
    appetite: appetite,
  );

  ScreeningResult run(ScreeningInput i) =>
      ScreeningCalculator.compute(i, config, WhoTables.empty, today: today);

  test('scenario 5: 18 months, MUAC 112 mm → MAS, CRENAS, orange, offline', () {
    final r = run(input(muac: 112));
    expect(r.ageMonths, 18);
    expect(r.classification, 'mas');
    expect(r.centre, 'crenas');
    expect(r.urgence, 'orange');
    expect(r.priorite, 'haute');
    expect(r.alerte, 'rouge');
    expect(r.needsReferral, isTrue);
    expect(r.nextCheck, DateTime(2026, 11, 11));
    expect(r.configVersion, 1);
    expect(ScreeningCalculator.motif(input(muac: 112), r), 'MAS – PB 112 mm');
  });

  test('age is computed from the birth date, as on the server (30.4375 days)', () {
    expect(ScreeningCalculator.ageDays(DateTime(2025, 5, 4), today), 549);
    expect(ScreeningCalculator.ageMonths(549), 18);
    expect(ScreeningCalculator.ageMonths(182), 5);
    expect(ScreeningCalculator.ageMonths(183), 6);
    // Across a daylight-saving change, days stay whole.
    expect(ScreeningCalculator.ageDays(DateTime(2026, 3, 1), DateTime(2026, 4, 1)), 31);
  });

  test('length correction of 0.7 cm around 731 days', () {
    expect(ScreeningCalculator.correctedLength(77.5, 'debout', 549), 78.2);
    expect(ScreeningCalculator.correctedLength(77.5, 'couche', 549), 77.5);
    expect(ScreeningCalculator.correctedLength(88.0, 'couche', 731), 87.3);
    expect(ScreeningCalculator.correctedLength(88.0, 'debout', 731), 88.0);
    expect(ScreeningCalculator.defaultPosition(730), 'couche');
    expect(ScreeningCalculator.defaultPosition(731), 'debout');
  });

  test('MUAC is refused under 6 months', () {
    final r = run(input(birth: DateTime(2026, 7, 1), muac: 110));
    expect(r.problems, contains(ScreeningProblem.muacOutsideAge));
    expect(r.classification, isNull);
  });

  test('dates: before birth or in the future are refused', () {
    expect(run(input(on: DateTime(2025, 1, 1))).problems, contains(ScreeningProblem.measureBeforeBirth));
    expect(run(input(on: DateTime(2026, 11, 5))).problems, contains(ScreeningProblem.measureInFuture));
  });

  test('60 months and more: outside the protocol', () {
    final r = run(input(birth: DateTime(2021, 11, 1), muac: 100));
    expect(r.problems, contains(ScreeningProblem.outsideAgeRange));
    expect(r.classification, isNull);
  });

  test('typing mistakes ask to check the measurement', () {
    expect(run(input(weight: 86, muac: 112)).outOfBounds, ['poids_kg']);
    expect(run(input(length: 7.75)).outOfBounds, ['taille_cm']);
    expect(run(input(muac: 11)).outOfBounds, ['pb_mm']);
    expect(run(input(muac: 112)).needsCheck, isFalse);
  });

  test('z-score outside the config range (±5) asks to check', () {
    final tables = WhoTables.fromFiles({
      WhoIndicator.wfl: 'sex\tlength\tl\tm\ts\tlorh\n2\t77.5\t-0.3521\t9.5032\t0.08295\tL\n',
    });
    final r = ScreeningCalculator.compute(input(weight: 4.0), config, tables, today: today);
    expect(r.zscores.whz, lessThan(-5));
    expect(r.zOutOfRange, isTrue);
    expect(r.classification, 'mas');
  });

  test('normal child: advice and next screening from the config', () {
    final r = run(input(muac: 140));
    expect(r.classification, 'normal');
    expect(r.needsReferral, isFalse);
    expect(r.adviceCode, 'depistage_normal');
    expect(r.nextCheck, DateTime(2027, 2, 2));
    expect(r.alerte, 'vert');
  });

  test('danger sign with MAS → CRENI, red, urgent', () {
    final r = run(input(muac: 110, signs: ['convulsions']));
    expect((r.classification, r.centre, r.urgence, r.priorite), ('mas', 'creni', 'rouge', 'urgente'));
  });

  group('referral code', () {
    test('format, check character and counter', () async {
      final gen = ReferralCodeGenerator(MemorySecretStore(), random: Random(1));
      final a = await gen.next();
      final b = await gen.next();
      expect(a, matches(RegExp(r'^TRK-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]$')));
      expect(a.substring(0, 9), b.substring(0, 9), reason: 'same install prefix');
      expect(a, isNot(b));
      expect(ReferralCodeGenerator.normalise(a), a);
    });

    test('dictated codes are understood; typos are caught', () {
      final code = ReferralCodeGenerator.format('7F3K9A', 2);
      expect(code, startsWith('TRK-7F3K-9A02-'));
      expect(ReferralCodeGenerator.normalise(code.toLowerCase().replaceAll('-', ' ')), code);
      final typo = code.replaceFirst('7F3K', '7F3X');
      expect(ReferralCodeGenerator.normalise(typo), isNull);
      final swapped = code.replaceFirst('7F3K', 'F73K');
      expect(ReferralCodeGenerator.normalise(swapped), isNull);
    });

    test('the counter grows past 2 characters and codes stay unique', () async {
      final store = MemorySecretStore();
      final gen = ReferralCodeGenerator(store, random: Random(2));
      final codes = <String>{};
      for (var i = 0; i < 1100; i++) {
        codes.add(await gen.next());
      }
      expect(codes.length, 1100);
      expect(codes.last.length, lessThanOrEqualTo(30), reason: 'server max_length 30');
    });

    test('a new prefix after the server refused a code', () async {
      final store = MemorySecretStore();
      final gen = ReferralCodeGenerator(store, random: Random(3));
      final a = await gen.next();
      await gen.rotatePrefix();
      final b = await gen.next();
      expect(a.substring(4, 9), isNot(b.substring(4, 9)));
    });
  });
}
