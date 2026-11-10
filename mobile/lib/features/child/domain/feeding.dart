import '../../../core/config/clinical_config.dart';

/// Food of the configuration (local Malagasy foods), with its WHO/UNICEF group.
class Food {
  const Food({
    required this.code,
    required this.group,
    required this.labels,
    this.custom = false,
    this.hidden = false,
  });

  /// A food typed by the user (code `perso_…`), kept on the phone.
  factory Food.custom({
    required String code,
    required int group,
    required String name,
    bool hidden = false,
  }) => Food(
    code: code,
    group: group,
    labels: {'fr': name, 'en': name, 'mg': name},
    custom: true,
    hidden: hidden,
  );

  final String code;
  final int group;
  final Map<String, Object?> labels;
  final bool custom;

  /// A custom food removed from the list: no longer offered, but the days it
  /// was noted still count its group.
  final bool hidden;

  String get name => labels['fr']?.toString() ?? code;
}

/// Common foods added to those of the configuration, so the choice is not
/// limited to one or two foods per group (e.g. only "Lait" for dairy).
/// Local Malagasy names; to be reviewed with the clinical configuration.
const List<Map<String, Object?>> commonFoods = [
  // 2 – Céréales, racines, tubercules
  {'code': 'katsaka', 'groupe': 2, 'fr': 'Maïs', 'en': 'Maize', 'mg': 'katsaka'},
  {'code': 'vomanga', 'groupe': 2, 'fr': 'Patate douce', 'en': 'Sweet potato', 'mg': 'vomanga'},
  {'code': 'ovy', 'groupe': 2, 'fr': 'Pomme de terre', 'en': 'Potato', 'mg': 'ovy'},
  {'code': 'saonjo', 'groupe': 2, 'fr': 'Taro', 'en': 'Taro', 'mg': 'saonjo'},
  {'code': 'mofo', 'groupe': 2, 'fr': 'Pain', 'en': 'Bread', 'mg': 'mofo'},
  {'code': 'paty', 'groupe': 2, 'fr': 'Pâtes', 'en': 'Pasta', 'mg': 'paty'},
  // 3 – Légumineuses, noix, graines
  {'code': 'voanjobory', 'groupe': 3, 'fr': 'Pois de terre', 'en': 'Bambara groundnut', 'mg': 'voanjobory'},
  {'code': 'kabaro', 'groupe': 3, 'fr': 'Pois du Cap', 'en': 'Lima beans', 'mg': 'kabaro'},
  {'code': 'lantilla', 'groupe': 3, 'fr': 'Lentilles', 'en': 'Lentils', 'mg': 'lantilla'},
  {'code': 'voanemba', 'groupe': 3, 'fr': 'Niébé', 'en': 'Cowpeas', 'mg': 'voanemba'},
  // 4 – Produits laitiers
  {'code': 'yaourt', 'groupe': 4, 'fr': 'Yaourt', 'en': 'Yoghurt', 'mg': 'yaourt'},
  {'code': 'fromazy', 'groupe': 4, 'fr': 'Fromage', 'en': 'Cheese', 'mg': 'fromazy'},
  {'code': 'habobo', 'groupe': 4, 'fr': 'Lait caillé', 'en': 'Curdled milk', 'mg': 'habobo'},
  {
    'code': 'ronono_vovoka',
    'groupe': 4,
    'fr': 'Lait en poudre',
    'en': 'Powdered milk',
    'mg': 'ronono vovoka',
  },
  // 5 – Viandes, poissons, volailles, abats
  {'code': 'akoho', 'groupe': 5, 'fr': 'Poulet', 'en': 'Chicken', 'mg': 'akoho'},
  {'code': 'henomby', 'groupe': 5, 'fr': 'Bœuf', 'en': 'Beef', 'mg': "hen'omby"},
  {'code': 'henakisoa', 'groupe': 5, 'fr': 'Porc', 'en': 'Pork', 'mg': 'henakisoa'},
  {'code': 'aty', 'groupe': 5, 'fr': 'Foie', 'en': 'Liver', 'mg': 'aty'},
  {'code': 'trondro_maina', 'groupe': 5, 'fr': 'Poisson séché', 'en': 'Dried fish', 'mg': 'trondro maina'},
  {'code': 'patsa', 'groupe': 5, 'fr': 'Crevettes séchées', 'en': 'Dried shrimp', 'mg': 'patsa'},
  // 6 – Œufs
  {'code': 'atody_gana', 'groupe': 6, 'fr': 'Œuf de cane', 'en': 'Duck egg', 'mg': 'atody gana'},
  {'code': 'atody_papelika', 'groupe': 6, 'fr': 'Œuf de caille', 'en': 'Quail egg', 'mg': 'atody papelika'},
  // 7 – Fruits et légumes riches en vitamine A
  {'code': 'karaoty', 'groupe': 7, 'fr': 'Carotte', 'en': 'Carrot', 'mg': 'karaoty'},
  {'code': 'papay', 'groupe': 7, 'fr': 'Papaye', 'en': 'Papaya', 'mg': 'papay'},
  {
    'code': 'vomanga_mena',
    'groupe': 7,
    'fr': 'Patate douce orange',
    'en': 'Orange sweet potato',
    'mg': 'vomanga mena',
  },
  {
    'code': 'ravimbomanga',
    'groupe': 7,
    'fr': 'Feuilles de patate douce',
    'en': 'Sweet potato leaves',
    'mg': 'ravimbomanga',
  },
  // 8 – Autres fruits et légumes
  {'code': 'voasary', 'groupe': 8, 'fr': 'Orange', 'en': 'Orange', 'mg': 'voasary'},
  {'code': 'mananasy', 'groupe': 8, 'fr': 'Ananas', 'en': 'Pineapple', 'mg': 'mananasy'},
  {'code': 'letsy', 'groupe': 8, 'fr': 'Litchi', 'en': 'Lychee', 'mg': 'letsy'},
  {'code': 'zavoka', 'groupe': 8, 'fr': 'Avocat', 'en': 'Avocado', 'mg': 'zavoka'},
  {'code': 'paoma', 'groupe': 8, 'fr': 'Pomme', 'en': 'Apple', 'mg': 'paoma'},
  {'code': 'voatabia', 'groupe': 8, 'fr': 'Tomate', 'en': 'Tomato', 'mg': 'voatabia'},
  {'code': 'laisoa', 'groupe': 8, 'fr': 'Chou', 'en': 'Cabbage', 'mg': 'laisoa'},
  {'code': 'baranjely', 'groupe': 8, 'fr': 'Aubergine', 'en': 'Eggplant', 'mg': 'baranjely'},
  {
    'code': 'tsaramaso_maitso',
    'groupe': 8,
    'fr': 'Haricots verts',
    'en': 'Green beans',
    'mg': 'tsaramaso maitso',
  },
  {'code': 'concombre', 'groupe': 8, 'fr': 'Concombre', 'en': 'Cucumber', 'mg': 'konkombra'},
];

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
  FeedingRules(this.config, {this.custom = const []});

  final ClinicalConfig config;

  /// Foods typed by the user, shown after the others of their group.
  final List<Food> custom;

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

  /// The foods, each one once: those of the configuration, the common foods,
  /// then the user's own. A code, or a name in a group, listed twice (e.g. the
  /// same pulse added by two regions) shows once.
  List<Food> get foods {
    final codes = <String>{};
    final names = <String>{};
    final groupNumbers = {for (final g in groups) g.number};
    bool keep(String code, int group, String name) => codes.add(code) && names.add('$group:${foodKey(name)}');
    return [
      for (final f in [
        ...asMapList(_section['aliments']),
        // Added foods only under a group the configuration still has.
        for (final c in commonFoods)
          if (groupNumbers.contains(asInt(c['groupe']))) c,
      ])
        if (f['code'] is String && asInt(f['groupe']) != null)
          if (keep(f['code']! as String, asInt(f['groupe'])!, localizedText(f, 'fr')))
            Food(code: f['code']! as String, group: asInt(f['groupe'])!, labels: f),
      for (final f in custom)
        if (groupNumbers.contains(f.group) && (f.hidden ? codes.add(f.code) : keep(f.code, f.group, f.name)))
          f,
    ];
  }

  /// A name compared without case, accents nor extra spaces.
  static String foodKey(String name) {
    const from = 'àâäáãèéêëìíîïòóôöõùúûüçñœ';
    const to = 'aaaaaeeeeiiiiooooouuuucne';
    final b = StringBuffer();
    for (final c in name.trim().toLowerCase().split('')) {
      final i = from.indexOf(c);
      b.write(i < 0 ? c : to[i]);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// True when [name] is already a food of [group], in any language.
  bool hasFood(int group, String name) {
    final key = foodKey(name);
    return foods.any(
      (f) =>
          f.group == group &&
          !f.hidden &&
          ['fr', 'en', 'mg'].any((l) => foodKey(localizedText(f.labels, l)) == key),
    );
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

// ------------------------------------------------------------ breastfeeding

/// What a baby under 6 months received besides breast milk, when the answer
/// to "uniquement du lait maternel ?" is no (stored codes, never translated).
const List<String> otherIntakes = ['eau', 'lait_infantile', 'aliments', 'autres'];

/// A feed: at the breast (with its duration) or expressed breast milk given
/// by cup or spoon (with its quantity). Expressed breast milk is still breast
/// milk: it keeps the feeding exclusive.
class BreastFeed {
  const BreastFeed({required this.id, required this.at, required this.type, this.minutes, this.millilitres});

  static const atBreast = 'sein';
  static const expressed = 'exprime';

  final String id;
  final DateTime at;

  /// [atBreast] or [expressed].
  final String type;
  final int? minutes;
  final int? millilitres;

  bool get isExpressed => type == expressed;
}

/// Totals of one day of feeds.
class FeedTotals {
  const FeedTotals({
    required this.feeds,
    required this.minutes,
    required this.expressedFeeds,
    required this.millilitres,
  });

  factory FeedTotals.of(Iterable<BreastFeed> feeds) {
    var count = 0, minutes = 0, expressed = 0, ml = 0;
    for (final f in feeds) {
      count++;
      minutes += f.minutes ?? 0;
      if (f.isExpressed) {
        expressed++;
        ml += f.millilitres ?? 0;
      }
    }
    return FeedTotals(feeds: count, minutes: minutes, expressedFeeds: expressed, millilitres: ml);
  }

  final int feeds;
  final int minutes;
  final int expressedFeeds;
  final int millilitres;
}

/// One day of the weekly summary of breastfeeding.
enum BreastfeedingDay {
  /// Only breast milk (at the breast or expressed).
  exclusive,

  /// Breast milk and something else (water, formula, food…).
  mixed,

  /// Nothing noted that day.
  notNoted,
}

/// The 7 days ending on [end] (oldest first), always 7, with the answer
/// noted for each: exclusive, mixed or not noted. A day before [birth] has no
/// status (null): it is shown, but neither counted nor tappable.
List<(DateTime, BreastfeedingDay?)> breastfeedingWeek({
  required Map<DateTime, String> answers,
  required DateTime end,
  required DateTime birth,
}) {
  final born = DateTime(birth.year, birth.month, birth.day);
  return [
    for (var i = 6; i >= 0; i--)
      () {
        final d = DateTime(end.year, end.month, end.day - i);
        if (d.isBefore(born)) return (d, null);
        final status = switch (answers[d]) {
          'exclusif' => BreastfeedingDay.exclusive,
          'mixte' => BreastfeedingDay.mixed,
          _ => BreastfeedingDay.notNoted,
        };
        return (d, status);
      }(),
  ];
}

/// "5 jours d'allaitement exclusif sur 7": the counts of a week, over the
/// days since birth only.
class WeekBalance {
  const WeekBalance({required this.exclusive, required this.mixed, required this.notNoted});

  factory WeekBalance.of(Iterable<(DateTime, BreastfeedingDay?)> days) {
    int count(BreastfeedingDay d) => days.where((e) => e.$2 == d).length;
    return WeekBalance(
      exclusive: count(BreastfeedingDay.exclusive),
      mixed: count(BreastfeedingDay.mixed),
      notNoted: count(BreastfeedingDay.notNoted),
    );
  }

  final int exclusive;
  final int mixed;
  final int notNoted;

  int get total => exclusive + mixed + notNoted;

  /// Share of exclusive days, 0 to 1.
  double get exclusiveShare => total == 0 ? 0 : exclusive / total;

  int count(BreastfeedingDay d) => switch (d) {
    BreastfeedingDay.exclusive => exclusive,
    BreastfeedingDay.mixed => mixed,
    BreastfeedingDay.notNoted => notNoted,
  };
}

/// Difficulties the mother can report (stored codes, never translated).
const List<String> breastfeedingDifficulties = [
  'douleur', // sore or cracked nipples
  'engorgement', // hard, swollen breasts
  'peu_de_lait', // fear of not having enough milk
  'prise_du_sein', // the baby latches badly or falls asleep at the breast
  'reprise_travail', // away from the baby (work, travel)
];

/// Stage of breastfeeding by the baby's age, for the personalised advice.
enum BreastfeedingStage {
  /// First week: colostrum, very frequent feeds, skin to skin.
  firstWeek,

  /// 1 to 6 weeks: feeds on demand, growth spurts.
  firstWeeks,

  /// 6 weeks to 4 months: a rhythm settles, night feeds go on.
  settled,

  /// 4 to 6 months: still breast milk only, prepare the foods of 6 months.
  beforeFoods,

  /// From 6 months: breastfeeding goes on with other foods.
  withFoods;

  static BreastfeedingStage of(int ageDays) => ageDays < 7
      ? firstWeek
      : ageDays < 42
      ? firstWeeks
      : ageDays < 120
      ? settled
      : ageDays < 183
      ? beforeFoods
      : withFoods;
}

/// The advice to show, most useful first: each difficulty reported, then
/// the way back to exclusive breastfeeding (a mixed day before 6 months),
/// then the advice of the baby's age. Codes, translated by the screen.
List<String> personalBreastfeedingTips({
  required int ageDays,
  required Set<String> difficulties,
  required bool mixedRecently,
}) {
  final stage = BreastfeedingStage.of(ageDays);
  return [
    for (final d in breastfeedingDifficulties)
      if (difficulties.contains(d)) 'difficulty_$d',
    if (mixedRecently && stage != BreastfeedingStage.withFoods) 'back_to_exclusive',
    'stage_${stage.name}',
  ];
}
