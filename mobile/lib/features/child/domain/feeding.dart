import '../../../core/config/clinical_config.dart';

/// Food of the configuration (local Malagasy foods), with its WHO/UNICEF group.
class Food {
  const Food({required this.code, required this.group, required this.labels});
  final String code;
  final int group;
  final Map<String, Object?> labels;
}

class FoodGroup {
  const FoodGroup({required this.number, required this.field, required this.labels});
  final int number;

  /// Server column, e.g. `g5_viande_poisson`.
  final String field;
  final Map<String, Object?> labels;
}

class Advice {
  const Advice({required this.code, required this.labels});
  final String code;
  final Map<String, Object?> labels;
}

/// One day of feeding for a child of 6 to 23 months.
class FeedingDay {
  const FeedingDay({required this.foods, this.meals = 0, this.milkFeeds = 0});

  /// Food codes eaten that day (pictograms tapped).
  final Set<String> foods;

  /// Meals of solid, semi-solid or soft food.
  final int meals;

  /// Milk feeds other than breast milk (for a child not breastfed).
  final int milkFeeds;
}

class FeedingIndicators {
  const FeedingIndicators({
    required this.groups,
    required this.groupCount,
    required this.groupTotal,
    required this.diversityMin,
    required this.diversityMet,
    required this.breastfed,
    required this.mealsRequired,
    required this.mealsMet,
    required this.acceptableMet,
    required this.advice,
  });

  final Set<int> groups;
  final int groupCount;
  final int groupTotal;
  final int diversityMin;

  /// Minimum dietary diversity (≥ 5 of 8 groups in the sample config).
  final bool diversityMet;
  final bool breastfed;

  /// Minimum meal frequency for this age and breastfeeding, or null if the
  /// configuration has no rule for this age.
  final int? mealsRequired;
  final bool mealsMet;

  /// Minimum acceptable diet: diversity and frequency (and, for a child not
  /// breastfed, the configured minimum of milk feeds).
  final bool acceptableMet;

  /// Concrete suggestions from the validated advice library.
  final List<Advice> advice;
}

/// Feeding rules (spec §6), all read from `alimentation_enfant` in the config.
class FeedingRules {
  FeedingRules(this.config);

  final ClinicalConfig config;

  Map<String, Object?> get _section => config.alimentationEnfant;

  int get exclusiveMaxMonths => asInt(_section['allaitement_exclusif_age_max_mois']) ?? 5;
  int get logMinMonths => asInt(_section['journal_age_min_mois']) ?? 6;
  int get logMaxMonths => asInt(_section['journal_age_max_mois']) ?? 23;

  /// The food groups, each number once, in order.
  List<FoodGroup> get groups {
    final byNumber = <int, FoodGroup>{};
    for (final g in asMapList(_section['groupes'])) {
      final n = asInt(g['numero']);
      final field = g['champ'];
      if (n == null || field is! String) continue;
      byNumber.putIfAbsent(n, () => FoodGroup(number: n, field: field, labels: g));
    }
    return byNumber.values.toList()..sort((a, b) => a.number.compareTo(b.number));
  }

  /// The foods, each one once: a code, or a name in a group, listed twice in
  /// the configuration (e.g. the same pulse added by two regions) shows once.
  List<Food> get foods {
    final codes = <String>{};
    final names = <String>{};
    return [
      for (final f in asMapList(_section['aliments']))
        if (f['code'] is String && asInt(f['groupe']) != null)
          if (codes.add(f['code']! as String) &&
              names.add('${asInt(f['groupe'])}:${localizedText(f, 'fr').trim().toLowerCase()}'))
            Food(code: f['code']! as String, group: asInt(f['groupe'])!, labels: f),
    ];
  }

  /// Foods sorted under their group, groups without food left out.
  List<(FoodGroup, List<Food>)> foodsByGroup() {
    final all = foods;
    return [
      for (final g in groups)
        if (all.any((f) => f.group == g.number))
          (
            g,
            [
              for (final f in all)
                if (f.group == g.number) f,
            ],
          ),
    ];
  }

  /// The breast-milk group (`g1_lait_maternel`).
  int get breastMilkGroup =>
      groups.firstWhere((g) => g.field.contains('lait_maternel'), orElse: () => groups.first).number;

  FeedingIndicators compute({required int ageMonths, required FeedingDay day}) {
    final byCode = {for (final f in foods) f.code: f};
    final eaten = {for (final c in day.foods) ?byCode[c]?.group};
    final breastfed = eaten.contains(breastMilkGroup);
    final min = asInt(_section['diversite_minimale_groupes']) ?? groups.length;
    final diversity = eaten.length >= min;

    Map<String, Object?>? rule;
    for (final r in asMapList(_section['frequence_minimale_repas'])) {
      final lo = asInt(r['age_mois_min']) ?? 0;
      final hi = asInt(r['age_mois_max']) ?? 999;
      if (ageMonths >= lo && ageMonths <= hi && r['allaite'] == breastfed) {
        rule = r;
        break;
      }
    }
    final required = asInt(rule?['repas']);
    final mealsMet = required != null && day.meals >= required;
    final milkMin = asInt(rule?['dont_lait_min']) ?? 0;
    final acceptable = diversity && mealsMet && (breastfed || day.milkFeeds >= milkMin);

    final adviceCodes = <String>{};
    final advice = <Advice>[
      for (final c in asMapList(_section['conseils']))
        if (c['si_groupes_absents'] is List &&
            (c['si_groupes_absents']! as List).every((g) => !eaten.contains(asInt(g))) &&
            adviceCodes.add(c['code']! as String))
          Advice(code: c['code']! as String, labels: c),
    ];

    return FeedingIndicators(
      groups: eaten,
      groupCount: eaten.length,
      groupTotal: groups.length,
      diversityMin: min,
      diversityMet: diversity,
      breastfed: breastfed,
      mealsRequired: required,
      mealsMet: mealsMet,
      acceptableMet: acceptable,
      advice: diversity ? const [] : advice,
    );
  }

  /// Server columns g1…g8 for a set of groups (journal_alimentaire).
  Map<String, bool> groupFields(Set<int> eaten) => {
    for (final g in groups) g.field: eaten.contains(g.number),
  };
}
