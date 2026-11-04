import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/config/rule_engine.dart';

import '../../helpers/config_fixture.dart';

/// Same cases as the server (Backend_serveur/nutrition/tests_classification.py,
/// ClassificationTest), on the same sample config: phone and server agree.
void main() {
  final mal = sampleConfig().malnutrition;

  Map<String, Object?> values({int ageMois = 18, Map<String, Object?> extra = const {}}) => {
    'age_mois': ageMois,
    'oedemes_bilateraux': 'aucun',
    'whz': null,
    'waz': null,
    'haz': null,
    'pb_mm': null,
    'signes_danger': <String>[],
    'complications_medicales': false,
    'appetit': 'non_teste',
    'difficultes_allaitement': false,
    ...extra,
  };

  (String?, String?, String?) classify({int ageMois = 18, Map<String, Object?> extra = const {}}) {
    final v = values(ageMois: ageMois, extra: extra);
    final c = RuleEngine.classify(mal, v);
    final o = RuleEngine.orient(mal, {...v, 'classification': c});
    return (c, o?['centre'] as String?, o?['urgence'] as String?);
  }

  test('scenario 5: MUAC 112 mm, no oedema nor complication → MAS, CRENAS, orange', () {
    expect(classify(extra: {'pb_mm': 112}), ('mas', 'crenas', 'orange'));
  });

  test('MAS with complication, danger sign or poor appetite → CRENI, red', () {
    for (final extra in [
      {'complications_medicales': true},
      {
        'signes_danger': ['convulsions'],
      },
      {'appetit': 'mauvais'},
    ]) {
      expect(classify(extra: {'pb_mm': 110, ...extra}), ('mas', 'creni', 'rouge'), reason: '$extra');
    }
  });

  test('good appetite stays at the CRENAS', () {
    expect(classify(extra: {'pb_mm': 110, 'appetit': 'bon'}).$2, 'crenas');
  });

  test('bilateral oedema is MAS whatever the other values', () {
    for (final grade in ['+', '++', '+++']) {
      expect(classify(extra: {'oedemes_bilateraux': grade, 'pb_mm': 140, 'whz': 0.5}).$1, 'mas');
    }
  });

  test('MUAC limits: 114 MAS, 115 MAM, 124 MAM, 125 normal', () {
    for (final (pb, expected) in [(114, 'mas'), (115, 'mam'), (124, 'mam'), (125, 'normal')]) {
      expect(classify(extra: {'pb_mm': pb}).$1, expected, reason: 'pb $pb');
    }
  });

  test('WHZ limits: -3.01 MAS, -3.00 MAM, -2.01 MAM, -2.00 normal', () {
    for (final (whz, expected) in [
      (-3.01, 'mas'),
      (-3.00, 'mam'),
      (-2.01, 'mam'),
      (-2.00, 'normal'),
      (1.20, 'normal'),
    ]) {
      expect(classify(extra: {'whz': whz}).$1, expected, reason: 'whz $whz');
    }
  });

  test('the most severe criterion wins', () {
    expect(classify(extra: {'whz': -2.5, 'pb_mm': 110}).$1, 'mas');
    expect(classify(extra: {'whz': -3.5, 'pb_mm': 130}).$1, 'mas');
  });

  test('MAM → CRENAM yellow; normal → no referral', () {
    expect(classify(extra: {'pb_mm': 120}), ('mam', 'crenam', 'jaune'));
    expect(classify(extra: {'pb_mm': 140}), ('normal', null, null));
  });

  test('nothing usable measured → normal', () {
    expect(classify().$1, 'normal');
  });

  test('under 6 months: infant at risk, always to a professional', () {
    expect(classify(ageMois: 4, extra: {'waz': -2.4}), ('nourrisson_a_risque', 'csb', 'orange'));
    expect(classify(ageMois: 4, extra: {'difficultes_allaitement': true}).$1, 'nourrisson_a_risque');
    expect(classify(ageMois: 5, extra: {'oedemes_bilateraux': '+'}).$1, 'nourrisson_a_risque');
    expect(classify(ageMois: 4).$1, 'normal');
    expect(
      classify(
        ageMois: 2,
        extra: {
          'signes_danger': ['ne_peut_pas_boire'],
        },
      ),
      ('nourrisson_a_risque', 'creni', 'rouge'),
    );
  });

  test('outside 0–59 months: not classified', () {
    expect(classify(ageMois: 60, extra: {'pb_mm': 100}), (null, null, null));
  });

  test('thresholds are read from the configuration, not the code', () {
    final custom = {
      ...mal,
      'classification': {
        'par_defaut': 'normal',
        'regles': [
          {
            'code': 'mas',
            'age_mois_min': 6,
            'si_un_des': [
              {'champ': 'pb_mm', 'inferieur_a': 120},
            ],
          },
        ],
      },
    };
    expect(RuleEngine.classify(custom, values(extra: {'pb_mm': 118})), 'mas');
    expect(RuleEngine.classify(mal, values(extra: {'pb_mm': 118})), 'mam');
  });

  test('operators: si_tous, ≤, ≥, egal on strings, missing value is false', () {
    final v = {'a': 5, 's': 'x', 'n': null};
    expect(RuleEngine.condition({'champ': 'a', 'inferieur_ou_egal_a': 5}, v), isTrue);
    expect(RuleEngine.condition({'champ': 'a', 'superieur_ou_egal_a': 6}, v), isFalse);
    expect(RuleEngine.condition({'champ': 'a', 'superieur_a': 4}, v), isTrue);
    expect(RuleEngine.condition({'champ': 's', 'egal': 'x'}, v), isTrue);
    expect(RuleEngine.condition({'champ': 'n', 'inferieur_a': 0}, v), isFalse);
    expect(RuleEngine.condition({'champ': 'n', 'non_vide': false}, v), isTrue);
    expect(RuleEngine.condition({'champ': 'a', 'inconnu': 1}, v), isFalse);
    expect(
      RuleEngine.applies({
        'si_tous': [
          {'champ': 'a', 'egal': 5},
          {
            'champ': 's',
            'dans': ['x', 'y'],
          },
        ],
      }, v),
      isTrue,
    );
  });
}
