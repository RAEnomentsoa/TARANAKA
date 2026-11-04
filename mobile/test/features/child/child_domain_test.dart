import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/growth/who_lms.dart';
import 'package:taranaka/features/child/domain/feeding.dart';
import 'package:taranaka/features/child/domain/growth_display.dart';
import 'package:taranaka/features/child/domain/vaccines.dart';

import '../../helpers/config_fixture.dart';

void main() {
  final config = sampleConfig();
  final rules = FeedingRules(config);

  group('feeding (8 WHO/UNICEF groups, from the config)', () {
    test('scenario 4: 9 months, vary + anana + breast milk → 3/8, insufficient, add an animal food', () {
      final r = rules.compute(
        ageMonths: 9,
        day: const FeedingDay(foods: {'vary', 'anana', 'lait_maternel'}, meals: 3),
      );
      expect(r.groupCount, 3);
      expect(r.groupTotal, 8);
      expect(r.diversityMet, isFalse);
      expect(r.breastfed, isTrue);
      expect(r.advice.first.code, 'ajouter_aliment_animal');
      expect(r.advice.first.labels['fr'], contains('œuf'));
      expect(r.acceptableMet, isFalse);
    });

    test('foods of the same group count once', () {
      final r = rules.compute(ageMonths: 12, day: const FeedingDay(foods: {'vary', 'mangahazo'}));
      expect(r.groupCount, 1);
    });

    test('5 groups reach the minimum diversity; no advice then', () {
      final r = rules.compute(
        ageMonths: 12,
        day: const FeedingDay(foods: {'lait_maternel', 'vary', 'voanjo', 'atody', 'anana'}, meals: 3),
      );
      expect(r.groupCount, 5);
      expect(r.diversityMet, isTrue);
      expect(r.advice, isEmpty);
      expect(r.mealsRequired, 3);
      expect(r.acceptableMet, isTrue);
    });

    test('minimum meal frequency by age and breastfeeding', () {
      int? required(int age, Set<String> foods) => rules
          .compute(
            ageMonths: age,
            day: FeedingDay(foods: foods),
          )
          .mealsRequired;
      expect(required(7, {'lait_maternel'}), 2);
      expect(required(9, {'lait_maternel'}), 3);
      expect(required(15, {'vary'}), 4);
    });

    test('a child not breastfed also needs the configured milk feeds', () {
      const foods = {'vary', 'voanjo', 'ronono', 'atody', 'anana'};
      final without = rules.compute(ageMonths: 15, day: const FeedingDay(foods: foods, meals: 4));
      expect(without.diversityMet && without.mealsMet, isTrue);
      expect(without.acceptableMet, isFalse);
      final withMilk = rules.compute(
        ageMonths: 15,
        day: const FeedingDay(foods: foods, meals: 4, milkFeeds: 2),
      );
      expect(withMilk.acceptableMet, isTrue);
    });

    test('advice applies only when all its groups are missing', () {
      final r = rules.compute(ageMonths: 9, day: const FeedingDay(foods: {'vary', 'atody'}));
      expect(r.advice.map((a) => a.code), isNot(contains('ajouter_aliment_animal')));
      expect(r.advice.map((a) => a.code), contains('ajouter_legumineuse'));
    });

    test('ages and server columns come from the config', () {
      expect(rules.exclusiveMaxMonths, 5);
      expect((rules.logMinMonths, rules.logMaxMonths), (6, 23));
      expect(rules.groupFields({1, 7})['g1_lait_maternel'], isTrue);
      expect(rules.groupFields({1, 7})['g5_viande_poisson'], isFalse);
    });
  });

  group('immunisation schedule (PEV from the config)', () {
    final birth = DateTime(2026, 1, 1);

    test('due dates from the birth date, statuses done / late / today / upcoming', () {
      final doses = VaccineSchedule.build(
        config,
        birthDate: birth,
        done: {'bcg': DateTime(2026, 1, 1)},
        today: DateTime(2026, 2, 12),
      );
      final byCode = {for (final d in doses) d.code: d};
      expect(byCode['bcg']!.status, DoseStatus.done);
      expect(byCode['vpo0']!.status, DoseStatus.late);
      expect(byCode['penta1']!.dueDate, DateTime(2026, 2, 12));
      expect(byCode['penta1']!.status, DoseStatus.dueToday);
      expect(byCode['rr1']!.status, DoseStatus.upcoming);
      expect(doses.length, 16);
      expect(doses.first.ageDays, 0);
    });
  });

  group('parent growth status (affichage_parent)', () {
    test('lowest z-score decides', () {
      expect(GrowthDisplay.status(config, const ZScores(whz: 0.4, waz: -1.0))!.code, 'sur_la_bonne_voie');
      expect(GrowthDisplay.status(config, const ZScores(whz: -2.5, waz: 0))!.code, 'a_surveiller');
      expect(GrowthDisplay.status(config, const ZScores(haz: -3.2))!.code, 'consulter');
      expect(GrowthDisplay.status(config, const ZScores(whz: -2.0))!.code, 'sur_la_bonne_voie');
    });

    test('no z-score (WHO tables missing): no status, never guessed', () {
      expect(GrowthDisplay.status(config, const ZScores()), isNull);
    });

    test('implausible z-score asks to check the measurement', () {
      expect(GrowthDisplay.implausible(config, const ZScores(waz: -5.1)), isTrue);
      expect(GrowthDisplay.implausible(config, const ZScores(waz: -4.9)), isFalse);
    });
  });
}
