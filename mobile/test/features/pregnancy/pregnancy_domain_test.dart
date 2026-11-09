import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/config/clinical_config.dart';
import 'package:taranaka/features/pregnancy/domain/pregnancy.dart';

import '../../helpers/config_fixture.dart';

void main() {
  final calc = PregnancyCalculator(sampleConfig());
  final today = DateTime(2026, 11, 4);

  test('scenario 3: DDR at D-84 → 12 SA + 0 d, due date DDR + 280, next ANC', () {
    final lmp = today.subtract(const Duration(days: 84));
    final p = PregnancyDates(lmp: lmp);
    final ga = calc.age(p, today)!;
    expect((ga.weeks, ga.days), (12, 0));
    expect(calc.dueDate(p), lmp.add(const Duration(days: 280)));
    expect(calc.dueDate(p), DateTime(2027, 5, 19));
    expect(calc.trimester(ga), 1);
    final contacts = calc.antenatal(p, const {}, today);
    expect(contacts.length, 8);
    expect(contacts.first.label, 12);
    expect(contacts.first.date, today);
    expect(contacts.first.status, ContactStatus.next);
    expect(contacts[1].label, 20);
    expect(contacts[1].date, lmp.add(const Duration(days: 140)));
    expect(contacts[1].status, ContactStatus.upcoming);
  });

  test('a term confirmed by a professional wins over the DDR', () {
    final p = PregnancyDates(
      lmp: today.subtract(const Duration(days: 84)),
      confirmedOn: DateTime(2026, 10, 28),
      confirmedAgeDays: 10 * 7 + 3, // 10 SA + 3 d on 28 Oct
    );
    final ga = calc.age(p, today)!;
    expect((ga.weeks, ga.days), (11, 3));
    expect(
      calc.dueDate(p),
      DateTime(2026, 10, 28).subtract(const Duration(days: 73)).add(const Duration(days: 280)),
    );
  });

  test('confirmed term alone is enough', () {
    final p = PregnancyDates(confirmedOn: today, confirmedAgeDays: 20 * 7);
    expect(calc.age(p, today)!.weeks, 20);
  });

  test('weeks and days across months and daylight-saving', () {
    final p = PregnancyDates(lmp: DateTime(2026, 3, 1));
    final ga = calc.age(p, DateTime(2026, 4, 5))!;
    expect((ga.weeks, ga.days), (5, 0));
  });

  test('trimesters: 13+6 is 1st, 14+0 is 2nd, 28+0 is 3rd', () {
    expect(calc.trimester(const GestationalAge(13 * 7 + 6)), 1);
    expect(calc.trimester(const GestationalAge(14 * 7)), 2);
    expect(calc.trimester(const GestationalAge(27 * 7 + 6)), 2);
    expect(calc.trimester(const GestationalAge(28 * 7)), 3);
  });

  test('ANC statuses: done, missed, next, upcoming', () {
    final lmp = DateTime(2026, 4, 1);
    final p = PregnancyDates(lmp: lmp);
    final at = lmp.add(const Duration(days: 27 * 7)); // 27 SA
    final contacts = calc.antenatal(p, {1: DateTime(2026, 6, 24)}, at);
    expect(contacts.map((c) => c.status).take(4).toList(), [
      ContactStatus.done,
      ContactStatus.missed,
      ContactStatus.missed,
      ContactStatus.next,
    ]);
    expect(contacts[4].status, ContactStatus.upcoming);
  });

  test('postnatal contacts from the delivery date (config: days 1, 3, 10, 42)', () {
    final p = PregnancyDates(lmp: DateTime(2026, 1, 1), deliveredOn: DateTime(2026, 10, 1));
    final contacts = calc.postnatal(p, const {}, DateTime(2026, 10, 5));
    expect(contacts.map((c) => c.label), [1, 3, 10, 42]);
    expect(contacts[0].status, ContactStatus.missed);
    expect(contacts[2].date, DateTime(2026, 10, 11));
    expect(contacts[2].status, ContactStatus.next);
  });

  test('daily movement count from 28 SA; first movements explained at 16–22 SA', () {
    expect(calc.movementsFromWeeks, 28);
    expect(calc.firstMovementsWeeks, [16, 22]);
  });

  test('women dietary diversity: 10 groups, at least 5', () {
    final diet = WomenDiet(sampleConfig());
    expect(diet.groups.length, 10);
    for (final lang in ['fr', 'mg', 'en']) {
      final names = [for (final g in diet.groups) localizedText(g, lang).toLowerCase()];
      expect(names.toSet().length, names.length, reason: 'no repeated meal group in $lang');
    }
    expect(diet.met({0, 1, 2, 3}), isFalse);
    expect(diet.met({0, 1, 2, 3, 4}), isTrue);
  });

  test('meal list: all groups shown, no word twice, in any language', () {
    loadConfigTranslations(
      (jsonDecode(File('assets/config/translations.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
    addTearDown(() => loadConfigTranslations(const {}));
    final diet = WomenDiet(sampleConfig());
    const links = {'et', 'à', 'de', 'en', 'and', 'in', 'sy', 'ary', 'a'};
    String norm(String w) {
      var x = w.toLowerCase();
      for (final (f, t) in [('é', 'e'), ('è', 'e'), ('ê', 'e'), ('œ', 'oe')]) {
        x = x.replaceAll(f, t);
      }
      return x.length > 3 && x.endsWith('s') ? x.substring(0, x.length - 1) : x;
    }

    for (final lang in ['fr', 'mg', 'en']) {
      final labels = [for (final (_, label) in diet.shown(lang)) label];
      expect(labels.length, 10, reason: '$lang: $labels');
      final words = [
        for (final l in labels)
          for (final w in l.split(RegExp(r"[^\p{L}']+", unicode: true)))
            if (w.isNotEmpty && !links.contains(w.toLowerCase())) norm(w),
      ];
      for (var i = 0; i < words.length; i++) {
        for (var j = i + 1; j < words.length; j++) {
          final (a, b) = (words[i], words[j]);
          final similar = a == b || (a.length >= 4 && b.length >= 4 && (a.startsWith(b) || b.startsWith(a)));
          expect(similar, isFalse, reason: '$lang: "$a" / "$b" in $labels');
        }
      }
    }
    final fr = [for (final (_, label) in diet.shown('fr')) label];
    expect(fr.where((l) => l.toLowerCase().contains('légume')).length, 1);
    expect(fr, contains('Légumes : tomate, oignon, chou, aubergine'));
  });

  test('meal list: an unknown label from a new configuration loses its repeated words', () {
    final json = (jsonDecode(File('assets/config/clinical_config_v1.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
    final content = (json['contenu'] as Map).cast<String, Object?>();
    content['alimentation_femme'] = {
      'diversite_minimale_groupes': 2,
      'groupes': ['Légumes verts', 'Fruits et légumes jaunes', 'Autres légumes', 'Lait', 'Produits laitiers'],
    };
    final diet = WomenDiet(ClinicalConfig.fromJson(json));
    expect(
      [for (final (i, l) in diet.shown('fr')) '$i=$l'],
      ['0=Légumes verts', '1=Fruits jaunes', '2=Tomate, oignon, chou, aubergine', '3=Lait', '4=Produits'],
    );
  });
}
