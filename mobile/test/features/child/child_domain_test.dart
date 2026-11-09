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
    test('more choices: dairy, meat, fruits and vegetables besides the configuration', () {
      final names = {for (final f in rules.foods) f.code: f.group};
      expect(names['ronono'], 4);
      expect([names['yaourt'], names['fromazy']], [4, 4]);
      expect([names['akoho'], names['aty']], [5, 5]);
      expect([names['karaoty'], names['voasary'], names['voatabia']], [7, 8, 8]);
      // Each food once.
      expect(rules.foods.map((f) => f.code).toSet(), hasLength(rules.foods.length));
    });

    test('a food typed by the user counts for its group; same name refused', () {
      final custom = Food.custom(code: 'perso_1', group: 5, name: 'Anguille');
      final withCustom = FeedingRules(config, custom: [custom]);
      expect(withCustom.foods.last.code, 'perso_1');
      final r = withCustom.compute(ageMonths: 9, day: const FeedingDay(foods: {'perso_1'}, meals: 1));
      expect(r.groups, {5});
      expect(withCustom.hasFood(5, ' anguille '), isTrue);
      expect(withCustom.hasFood(4, 'Yaourt'), isTrue);
      expect(withCustom.hasFood(4, 'yaourt'), isTrue);
      expect(withCustom.hasFood(4, 'Kéfir'), isFalse);
      // Removed (hidden): no longer offered, past days still count it.
      final hidden = FeedingRules(
        config,
        custom: [Food.custom(code: 'perso_1', group: 5, name: 'Anguille', hidden: true)],
      );
      expect(hidden.hasFood(5, 'Anguille'), isFalse);
      expect(hidden.compute(ageMonths: 9, day: const FeedingDay(foods: {'perso_1'})).groups, {5});
    });

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
      expect(byCode['vpo0']!.status, DoseStatus.expired); // given before 14 days only
      expect(byCode['penta1']!.dueDate, DateTime(2026, 2, 12));
      expect(byCode['penta1']!.status, DoseStatus.dueToday);
      expect(byCode['var1']!.status, DoseStatus.upcoming);
      expect(doses.first.ageDays, 0);
    });

    test('PEV Madagascar: doses and ages (0, 6/10/14 weeks, 9 and 15 months)', () {
      final doses = VaccineSchedule.build(config, birthDate: birth, done: const {}, today: birth);
      final ages = {for (final d in doses) d.code: d.ageDays};
      expect(ages, {
        'bcg': 0,
        'vpo0': 0,
        'penta1': 42,
        'vpo1': 42,
        'pcv1': 42,
        'rota1': 42,
        'penta2': 70,
        'vpo2': 70,
        'pcv2': 70,
        'rota2': 70,
        'penta3': 98,
        'vpo3': 98,
        'pcv3': 98,
        'vpi1': 98,
        'vpi2': 274,
        'var1': 274,
        'var2': 456,
      });
      expect(doses.every((d) => !d.name.contains('OMS')), isTrue);
    });

    test('doses saved under a former code count (vpi, rr1, rr2)', () {
      final doses = VaccineSchedule.build(
        config,
        birthDate: birth,
        done: const {},
        records: {'rr1': VaccineRecord(code: 'rr1', date: DateTime(2026, 10, 2), centre: 'CSB2')},
        today: DateTime(2026, 11, 1),
      );
      final var1 = doses.firstWhere((d) => d.code == 'var1');
      expect(var1.status, DoseStatus.done);
      expect(var1.record!.centre, 'CSB2');
      expect(var1.record!.code, 'var1');
    });

    test('VPO 0 after 14 days and Rotavirus after 24 months are no longer given', () {
      List<VaccineDose> at(DateTime today) =>
          VaccineSchedule.build(config, birthDate: birth, done: const {}, today: today);
      DoseStatus s(DateTime t, String code) => at(t).firstWhere((d) => d.code == code).status;
      expect(s(DateTime(2026, 1, 10), 'vpo0'), DoseStatus.late);
      expect(s(DateTime(2026, 1, 20), 'vpo0'), DoseStatus.expired);
      expect(s(DateTime(2027, 6, 1), 'rota1'), DoseStatus.late);
      expect(s(DateTime(2028, 1, 5), 'rota1'), DoseStatus.expired);
      expect(s(DateTime(2028, 1, 5), 'penta1'), DoseStatus.late);
    });

    test('VAR 2 is late only after 18 months', () {
      DoseStatus s(DateTime t) => VaccineSchedule.build(
        config,
        birthDate: birth,
        done: const {},
        today: t,
      ).firstWhere((d) => d.code == 'var2').status;
      expect(s(DateTime(2027, 5, 1)), DoseStatus.upcoming);
      expect(s(DateTime(2027, 6, 15)), DoseStatus.upcoming);
      expect(s(DateTime(2027, 7, 15)), DoseStatus.late);
    });

    test('checkDate: before birth, too early, too soon after the previous dose', () {
      final today = DateTime(2026, 6, 1);
      final doses = VaccineSchedule.build(
        config,
        birthDate: birth,
        done: {'penta1': DateTime(2026, 2, 12)},
        today: today,
      );
      final penta2 = doses.firstWhere((d) => d.code == 'penta2');
      List<DoseDateIssue> check(DateTime d) =>
          VaccineSchedule.checkDate(penta2, d, birthDate: birth, today: today, all: doses);
      expect(check(DateTime(2026, 3, 12)), isEmpty);
      expect(check(DateTime(2026, 3, 1)), [DoseDateIssue.beforeMinAge, DoseDateIssue.tooSoonAfterPrevious]);
      expect(check(DateTime(2025, 12, 1)), contains(DoseDateIssue.beforeBirth));
      expect(check(DateTime(2026, 7, 1)), contains(DoseDateIssue.inFuture));
      final rota1 = doses.firstWhere((d) => d.code == 'rota1');
      expect(
        VaccineSchedule.checkDate(
          rota1,
          DateTime(2028, 2, 1),
          birthDate: birth,
          today: DateTime(2028, 3, 1),
          all: doses,
        ),
        contains(DoseDateIssue.afterLastDay),
      );
    });

    test('next appointment: late doses first, else the earliest date', () {
      final early = VaccineSchedule.build(
        config,
        birthDate: birth,
        done: {'bcg': birth, 'vpo0': birth},
        today: DateTime(2026, 1, 20),
      );
      final (date, doses) = VaccineSchedule.nextAppointment(early, DateTime(2026, 1, 20))!;
      expect(date, DateTime(2026, 2, 12));
      expect(doses.map((d) => d.code).toSet(), {'penta1', 'vpo1', 'pcv1', 'rota1'});

      final late = VaccineSchedule.build(
        config,
        birthDate: birth,
        done: {'bcg': birth, 'vpo0': birth},
        today: DateTime(2026, 3, 1),
      );
      final (lateDate, lateDoses) = VaccineSchedule.nextAppointment(late, DateTime(2026, 3, 1))!;
      expect(lateDate, DateTime(2026, 3, 1));
      expect(lateDoses.every((d) => d.status == DoseStatus.late), isTrue);
    });

    test('reminders 7 days before, the day before and when late', () {
      final now = DateTime(2026, 1, 20, 12);
      final doses = VaccineSchedule.build(
        config,
        birthDate: birth,
        done: {'bcg': birth, 'vpo0': birth},
        today: now,
      );
      final reminders = vaccineReminders(doses, now);
      final forPenta1 = reminders.where((r) => r.due == DateTime(2026, 2, 12)).toList();
      expect(forPenta1.map((r) => (r.kind, r.at)), [
        (VaccineReminderKind.weekBefore, DateTime(2026, 2, 5, 9)),
        (VaccineReminderKind.dayBefore, DateTime(2026, 2, 11, 9)),
        (VaccineReminderKind.late, DateTime(2026, 2, 13, 9)),
      ]);
      expect(forPenta1.first.doses.length, 4);
      expect(forPenta1.first.key('c1'), 'vaccin-c1-weekBefore-2026-02-12');
      // Nothing for the doses received; all in the future, in order.
      expect(reminders.every((r) => r.at.isAfter(now)), isTrue);
      expect(reminders.any((r) => r.doses.any((d) => d.code == 'bcg')), isFalse);
    });

    test('a late reminder stops once the dose can no longer be given', () {
      final now = DateTime(2026, 2, 1, 12);
      final doses = VaccineSchedule.build(config, birthDate: birth, done: {'bcg': birth}, today: now);
      expect(doses.firstWhere((d) => d.code == 'vpo0').status, DoseStatus.expired);
      expect(vaccineReminders(doses, now).any((r) => r.doses.any((d) => d.code == 'vpo0')), isFalse);
    });

    test('catch-up advice comes from the configuration', () {
      expect(VaccineSchedule.catchUpAdvice(config), isNotEmpty);
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

  group('breastfeeding', () {
    test('exclusive up to 5 completed months, food diary from 6 months', () {
      expect(rules.exclusiveMaxMonths, 5);
      expect(rules.logMinMonths, 6);
    });

    test('weekly summary: exclusive, mixed and not noted days, never before birth', () {
      final end = DateTime(2026, 11, 9);
      final week = breastfeedingWeek(
        answers: {
          DateTime(2026, 11, 9): 'exclusif',
          DateTime(2026, 11, 8): 'mixte',
          DateTime(2026, 11, 6): 'exclusif',
          DateTime(2026, 11, 5): 'aucun',
        },
        end: end,
        birth: DateTime(2026, 10, 1),
      );
      expect(week, hasLength(7));
      expect(week.first.$1, DateTime(2026, 11, 3));
      expect(week.last, (end, BreastfeedingDay.exclusive));
      expect(week.where((d) => d.$2 == BreastfeedingDay.exclusive), hasLength(2));
      expect(week.where((d) => d.$2 == BreastfeedingDay.mixed), hasLength(1));
      expect(week.where((d) => d.$2 == BreastfeedingDay.notNoted), hasLength(4));

      final newborn = breastfeedingWeek(answers: const {}, end: end, birth: DateTime(2026, 11, 7));
      expect(newborn.map((d) => d.$1), [DateTime(2026, 11, 7), DateTime(2026, 11, 8), DateTime(2026, 11, 9)]);
    });

    test('feeds of a day: count, minutes at the breast, millilitres of expressed milk', () {
      final t = FeedTotals.of([
        BreastFeed(id: 'a', at: DateTime(2026, 11, 9, 6), type: BreastFeed.atBreast, minutes: 15),
        BreastFeed(id: 'b', at: DateTime(2026, 11, 9, 9), type: BreastFeed.atBreast, minutes: 10),
        BreastFeed(id: 'c', at: DateTime(2026, 11, 9, 12), type: BreastFeed.expressed, millilitres: 60),
      ]);
      expect((t.feeds, t.minutes, t.expressedFeeds, t.millilitres), (3, 25, 1, 60));
      expect(otherIntakes, ['eau', 'lait_infantile', 'aliments', 'autres']);
    });
  });
}
