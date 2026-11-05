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

  List<FoodGroup> get groups => [
    for (final g in asMapList(_section['groupes']))
      FoodGroup(number: asInt(g['numero'])!, field: g['champ']! as String, labels: g),
  ];

  List<Food> get foods => [
    for (final f in asMapList(_section['aliments']))
      Food(code: f['code']! as String, group: asInt(f['groupe'])!, labels: f),
  ];

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

    final advice = <Advice>[
      for (final c in asMapList(_section['conseils']))
        if (c['si_groupes_absents'] is List &&
            (c['si_groupes_absents']! as List).every((g) => !eaten.contains(asInt(g))))
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
