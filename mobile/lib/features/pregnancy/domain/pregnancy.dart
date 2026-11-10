import '../../../core/config/clinical_config.dart';
import '../../../core/util/clock.dart';

/// Gestational age in weeks of amenorrhoea (SA) + days.
class GestationalAge {
  const GestationalAge(this.totalDays);
  final int totalDays;

  int get weeks => totalDays ~/ 7;
  int get days => totalDays % 7;
}

/// A pregnancy as entered by the woman (spec §5): last menstrual period (DDR),
/// a term confirmed by a professional (ultrasound or consultation, expressed
/// as a gestational age on the day of the exam), or directly the expected due
/// date (DPA) given by a professional – in the future, or in the past for a
/// follow-up entered afterwards or a correction.
class PregnancyDates {
  const PregnancyDates({this.lmp, this.confirmedOn, this.confirmedAgeDays, this.deliveredOn, this.dueOn});

  final DateTime? lmp;
  final DateTime? confirmedOn;
  final int? confirmedAgeDays;
  final DateTime? deliveredOn;

  /// DPA entered as such (null when it is computed from the DDR or the term).
  final DateTime? dueOn;

  bool get hasConfirmedTerm => confirmedOn != null && confirmedAgeDays != null;
}

enum ContactStatus { done, missed, next, upcoming }

class CareContact {
  const CareContact({
    required this.number,
    required this.date,
    required this.label,
    required this.status,
    this.doneOn,
    DateTime? plannedDate,
  }) : plannedDate = plannedDate ?? date;

  /// 1-based, as in the national calendar.
  final int number;

  /// Date of the contact: the one chosen by the user, else the planned one.
  final DateTime date;

  /// Date of the national calendar, before any change by the user.
  final DateTime plannedDate;

  /// The user changed the date of this contact.
  bool get moved => date != plannedDate;

  /// SA for antenatal contacts, days after birth for postnatal ones, always
  /// reckoned on [date]: a moved contact never shows the SA of the calendar.
  final int label;
  final ContactStatus status;
  final DateTime? doneOn;
}

/// Calculations of "Ma grossesse". Durations and calendars come from the
/// configuration (`grossesse`, `calendrier_cpn`, `calendrier_postnatal`).
class PregnancyCalculator {
  PregnancyCalculator(this.config);

  final ClinicalConfig config;

  Map<String, Object?> get _g => config.grossesse;

  /// Naegele: DDR + 280 days in the sample configuration.
  int get naegeleDays => asInt(_g['duree_naegele_jours']) ?? 280;
  bool get confirmedTermWins => _g['terme_confirme_prioritaire'] != false;

  /// From this SA, the daily count of movements is advised. The journal itself
  /// is open at any SA: the mother can note what she feels whenever she wants.
  int get movementsFromWeeks => asInt(_g['journal_mouvements_a_partir_sa']) ?? 28;
  List<int> get firstMovementsWeeks =>
      (_g['premiers_mouvements_sa'] as List?)?.map((e) => asInt(e)!).toList() ?? const [16, 22];

  /// Day 0 of the pregnancy dating: the DDR, or the date implied by the
  /// confirmed term (which wins when the configuration says so), or, when only
  /// the DPA is known, the DPA minus the Naegele duration.
  DateTime? referenceDate(PregnancyDates p) {
    final confirmed = p.hasConfirmedTerm ? addDays(p.confirmedOn!, -p.confirmedAgeDays!) : null;
    if (confirmed != null && (confirmedTermWins || p.lmp == null)) return confirmed;
    if (p.lmp != null) return dateOnly(p.lmp!);
    if (p.dueOn != null) return addDays(p.dueOn!, -naegeleDays);
    return null;
  }

  GestationalAge? age(PregnancyDates p, DateTime today) {
    final ref = referenceDate(p);
    if (ref == null) return null;
    return GestationalAge(daysBetween(ref, today));
  }

  /// Date probable d'accouchement.
  DateTime? dueDate(PregnancyDates p) {
    if (p.dueOn != null && p.lmp == null && !p.hasConfirmedTerm) return dateOnly(p.dueOn!);
    final ref = referenceDate(p);
    return ref == null ? null : addDays(ref, naegeleDays);
  }

  /// Upper limits of a blood pressure that needs a consultation (mmHg), and
  /// of a fever (°C). From `grossesse` in the configuration when it has them.
  int get highSystolic => asInt(_g['tension_alerte_systolique']) ?? 140;
  int get highDiastolic => asInt(_g['tension_alerte_diastolique']) ?? 90;
  double get feverFrom => asNum(_g['fievre_a_partir_c'])?.toDouble() ?? 38;

  /// Trimester from completed weeks: 1st until 13 SA + 6 d, 2nd until 27 SA + 6 d,
  /// then 3rd. These are the usual obstetric definitions, read from the
  /// configuration when it provides `grossesse.trimestres_debut_sa`.
  int trimester(GestationalAge ga) {
    final starts = (_g['trimestres_debut_sa'] as List?)?.map((e) => asInt(e)!).toList() ?? const [0, 14, 28];
    var t = 1;
    for (var i = 0; i < starts.length; i++) {
      if (ga.weeks >= starts[i]) t = i + 1;
    }
    return t;
  }

  /// Antenatal contacts (spec §5: OMS 2016, 8 contacts; dates from the
  /// national calendar in the configuration). [moved]: dates changed by the
  /// user, by contact number.
  List<CareContact> antenatal(
    PregnancyDates p,
    Map<int, DateTime> done,
    DateTime today, {
    Map<int, DateTime> moved = const {},
  }) {
    final ref = referenceDate(p);
    if (ref == null) return const [];
    final weeks =
        (config.calendrierCpn['contacts_semaines_amenorrhee'] as List?)?.map((e) => asInt(e)!).toList() ??
        const <int>[];
    return _contacts(
      [for (final w in weeks) addDays(ref, w * 7)],
      (date) => daysBetween(ref, date) ~/ 7,
      done,
      moved,
      today,
    );
  }

  /// Postnatal contacts after the delivery (OMS 2022: at least 4 in 6 weeks).
  List<CareContact> postnatal(
    PregnancyDates p,
    Map<int, DateTime> done,
    DateTime today, {
    Map<int, DateTime> moved = const {},
  }) {
    final birth = p.deliveredOn;
    if (birth == null) return const [];
    final days =
        (config.calendrierPostnatal['contacts_jours_apres_accouchement'] as List?)
            ?.map((e) => asInt(e)!)
            .toList() ??
        const <int>[];
    return _contacts(
      [for (final d in days) addDays(birth, d)],
      (date) => daysBetween(birth, date),
      done,
      moved,
      today,
    );
  }

  List<CareContact> _contacts(
    List<DateTime> planned,
    int Function(DateTime) labelOn,
    Map<int, DateTime> done,
    Map<int, DateTime> moved,
    DateTime today,
  ) {
    final t = dateOnly(today);
    var nextGiven = false;
    return [
      for (var i = 0; i < planned.length; i++)
        () {
          final number = i + 1;
          final date = moved[number] == null ? planned[i] : dateOnly(moved[number]!);
          final label = labelOn(date);
          ContactStatus status;
          if (done.containsKey(number)) {
            status = ContactStatus.done;
          } else if (date.isBefore(t)) {
            status = ContactStatus.missed;
          } else if (!nextGiven) {
            status = ContactStatus.next;
            nextGiven = true;
          } else {
            status = ContactStatus.upcoming;
          }
          return CareContact(
            number: number,
            date: date,
            plannedDate: planned[i],
            label: label,
            status: status,
            doneOn: done[number],
          );
        }(),
    ];
  }
}

/// What a food group brings, for the advice on the missing groups.
enum DietKind { staple, protein, animal, leaves, fruitVegetable }

/// The advice shown after the day's groups are ticked.
enum DietAdvice { fruitVegetable, animal, protein, leaves, varied }

/// Women's dietary diversity (MDD-W, 10 groups, optional; spec §5).
class WomenDiet {
  WomenDiet(this.config);
  final ClinicalConfig config;

  static const _languages = ['fr', 'mg', 'en'];

  /// The groups as written in the configuration (plain text or `{fr, mg, en}`),
  /// each name once in every language: a group whose name, in any language,
  /// repeats an earlier one is left out (so "Légumes" never shows twice).
  /// The same list in every language, so the saved indices stay valid.
  List<Object> get groups {
    final seen = {for (final l in _languages) l: <String>{}};
    String key(Object g, String lang) =>
        localizedText(g, lang).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final result = <Object>[];
    for (final g in (config.alimentationFemme['groupes'] as List?) ?? const <Object?>[]) {
      if (g == null || key(g, 'fr').isEmpty) continue;
      if (_languages.any((l) => seen[l]!.contains(key(g, l)))) continue;
      for (final l in _languages) {
        seen[l]!.add(key(g, l));
      }
      result.add(g);
    }
    return result;
  }

  /// Labels shown for the MDD-W groups of the configuration, in short words
  /// that never repeat one another ("Légumes" once, "Fruits" once…), keyed by
  /// the French label of the configuration. Display only: the configuration
  /// and the saved indices are unchanged.
  static const _displayLabels = <String, Map<String, String>>{
    'céréales, racines, tubercules et plantains': {
      'fr': 'Céréales, racines, tubercules et plantains',
      'en': 'Grains, white roots, tubers and plantains',
      'mg': 'Voamaina, fakany, mangahazo, ovy ary akondro masaka',
    },
    'légumineuses': {
      'fr': 'Haricots, pois et lentilles',
      'en': 'Beans, peas and lentils',
      'mg': 'Tsaramaso, voanjobory, lentilles',
    },
    'noix et graines': {'fr': 'Noix et graines', 'en': 'Nuts and seeds', 'mg': 'Voanjo sy voa'},
    'lait et produits laitiers': {
      'fr': 'Produits laitiers',
      'en': 'Dairy products',
      'mg': 'Ronono sy vokatra avy aminy',
    },
    'viandes, volailles et poissons': {
      'fr': 'Viandes, volailles et poissons',
      'en': 'Meat, poultry and fish',
      'mg': 'Hena, akoho ary trondro',
    },
    'œufs': {'fr': 'Œufs', 'en': 'Eggs', 'mg': 'Atody'},
    'légumes à feuilles vert foncé': {
      'fr': 'Brèdes et feuilles vert foncé',
      'en': 'Dark green leaves',
      'mg': 'Anana maitso mavana',
    },
    'autres fruits et légumes riches en vitamine a': {
      'fr': 'Riches en vitamine A (orange ou jaune)',
      'en': 'Rich in vitamin A (orange or yellow)',
      'mg': 'Manankarena vitamina A (volomboasary na mavo)',
    },
    'autres légumes': {'fr': 'Légumes', 'en': 'Vegetables', 'mg': 'Legioma'},
    'autres fruits': {'fr': 'Fruits', 'en': 'Fruits', 'mg': 'Voankazo'},
  };

  /// Common Malagasy foods of each group, shown under its name ("Ex. : riz,
  /// manioc, patate douce, etc."): a few examples, never the whole list.
  /// Keyed like [_displayLabels]; display only.
  static const _examples = <String, Map<String, String>>{
    'céréales, racines, tubercules et plantains': {
      'fr': 'riz, manioc, patate douce, maïs, pain, etc.',
      'en': 'rice, cassava, sweet potato, maize, bread, etc.',
      'mg': 'vary, mangahazo, vomanga, katsaka, mofo, sns.',
    },
    'légumineuses': {
      'fr': 'voanjobory, haricots, lentilles, pois du Cap, etc.',
      'en': 'bambara groundnut (voanjobory), beans, lentils, lima beans, etc.',
      'mg': 'voanjobory, tsaramaso, lantily, kabaro, sns.',
    },
    'noix et graines': {
      'fr': 'arachides, noix de cajou, graines de sésame, etc.',
      'en': 'peanuts, cashew nuts, sesame seeds, etc.',
      'mg': 'voanjo, voanakazo, voamaintilany, sns.',
    },
    'lait et produits laitiers': {
      'fr': 'lait, yaourt, lait caillé, fromage, etc.',
      'en': 'milk, yoghurt, curdled milk, cheese, etc.',
      'mg': 'ronono, yaorta, ronono nandriana, fromazy, sns.',
    },
    'viandes, volailles et poissons': {
      'fr': 'zébu, poulet, petits poissons séchés, crevettes, foie, etc.',
      'en': 'zebu, chicken, small dried fish, shrimps, liver, etc.',
      'mg': "hen'omby, akoho, trondro madinika maina, patsa, aty, sns.",
    },
    'œufs': {
      'fr': 'œufs de poule, de cane, etc.',
      'en': 'hen or duck eggs, etc.',
      'mg': "atodin'akoho, atodin-gana, sns.",
    },
    'légumes à feuilles vert foncé': {
      'fr': 'anamamy, ravitoto, anamalaho, brèdes mafane, etc.',
      'en': 'anamamy, cassava leaves (ravitoto), anamalaho, etc.',
      'mg': 'anamamy, ravitoto, anamalaho, anamafana, sns.',
    },
    'autres fruits et légumes riches en vitamine a': {
      'fr': 'carotte, citrouille, mangue, papaye, patate douce orange, etc.',
      'en': 'carrot, pumpkin, mango, papaya, orange sweet potato, etc.',
      'mg': 'karaoty, voatavo, manga, papay, vomanga volomboasary, sns.',
    },
    'autres légumes': {
      'fr': 'tomate, oignon, chou, haricot vert, aubergine, etc.',
      'en': 'tomato, onion, cabbage, green beans, eggplant, etc.',
      'mg': 'voatabia, tongolo, laisoa, tsaramaso maitso, baranjely, sns.',
    },
    'autres fruits': {
      'fr': 'banane, orange, ananas, letchi, goyave, etc.',
      'en': 'banana, orange, pineapple, lychee, guava, etc.',
      'mg': 'akondro, voasary, mananasy, letisy, goavy, sns.',
    },
  };

  /// What each group brings, for the advice on the missing groups (keyed like
  /// [_displayLabels]).
  static const _kinds = <String, DietKind>{
    'céréales, racines, tubercules et plantains': DietKind.staple,
    'légumineuses': DietKind.protein,
    'noix et graines': DietKind.protein,
    'lait et produits laitiers': DietKind.animal,
    'viandes, volailles et poissons': DietKind.animal,
    'œufs': DietKind.animal,
    'légumes à feuilles vert foncé': DietKind.leaves,
    'autres fruits et légumes riches en vitamine a': DietKind.fruitVegetable,
    'autres légumes': DietKind.fruitVegetable,
    'autres fruits': DietKind.fruitVegetable,
  };

  static String _key(Object g) => localizedText(g, 'fr').trim().toLowerCase();

  /// Examples of group [index] of [groups] in [lang], or null (group unknown).
  String? examples(int index, String lang) {
    final all = groups;
    if (index < 0 || index >= all.length) return null;
    final known = _examples[_key(all[index])];
    return known?[lang] ?? known?['fr'];
  }

  /// One simple, kind piece of advice for a day, from the groups not ticked:
  /// fruits or vegetables first, then foods from animals, then pulses and
  /// nuts, then dark green leaves. [DietAdvice.varied] when none is missing;
  /// null before anything is ticked.
  DietAdvice? advice(Set<int> eaten) {
    if (eaten.isEmpty) return null;
    final all = groups;
    final kinds = {
      for (final i in eaten)
        if (i >= 0 && i < all.length) ?_kinds[_key(all[i])],
    };
    // Only the kinds this configuration has can be missing.
    final available = {for (final g in all) ?_kinds[_key(g)]};
    bool missing(DietKind k) => available.contains(k) && !kinds.contains(k);
    if (missing(DietKind.fruitVegetable)) return DietAdvice.fruitVegetable;
    if (missing(DietKind.animal)) return DietAdvice.animal;
    if (missing(DietKind.protein)) return DietAdvice.protein;
    if (missing(DietKind.leaves)) return DietAdvice.leaves;
    return DietAdvice.varied;
  }

  /// Small linking words: the only words allowed to appear more than once.
  static const _linkWords = {
    'et', 'a', 'à', 'au', 'aux', 'de', 'des', 'du', 'd', 'en', 'la', 'le', 'les', 'l', 'ou', //
    'and', 'or', 'in', 'of', 'the', //
    'sy', 'ary', 'na',
  };

  static final _token = RegExp(r"[\p{L}\p{N}'’-]+|[^\p{L}\p{N}'’-]+", unicode: true);
  static final _isWord = RegExp(r"^[\p{L}\p{N}]", unicode: true);

  /// A word compared without case, accents or plural ("Légumes" = "legume").
  static String _norm(String word) {
    const accents = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', //
      'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'œ': 'oe', 'æ': 'ae',
    };
    var w = word.toLowerCase();
    accents.forEach((from, to) => w = w.replaceAll(from, to));
    return w.length > 3 && (w.endsWith('s') || w.endsWith('x')) ? w.substring(0, w.length - 1) : w;
  }

  /// Same word, or one built on the other ("lait" and "laitiers").
  static bool _similar(String a, String b) =>
      a == b || (a.length >= 4 && b.length >= 4 && (a.startsWith(b) || b.startsWith(a)));

  /// [label] without the words already shown in the list ([seen], updated).
  /// Only needed for labels that [_displayLabels] does not know (a new
  /// configuration): the known ones never repeat.
  static String _withoutRepeats(String label, List<String> seen) {
    final kept = <String>[];
    var removed = false;
    for (final m in _token.allMatches(label)) {
      final t = m.group(0)!;
      if (!_isWord.hasMatch(t) || _linkWords.contains(t.toLowerCase())) {
        kept.add(t);
        continue;
      }
      final w = _norm(t);
      if (seen.any((s) => _similar(s, w))) {
        removed = true;
        // Also drop the linking word just before it ("fruits et légumes" → "fruits").
        var end = kept.length;
        while (end > 0 && kept[end - 1].trim().isEmpty) {
          end--;
        }
        if (end > 0 && _linkWords.contains(kept[end - 1].toLowerCase())) {
          kept.removeRange(end - 1, kept.length);
        }
        continue;
      }
      seen.add(w);
      kept.add(t);
    }
    if (!removed) return label;
    // Tidy what the removed words left: spaces, commas, dangling "et".
    final link = _linkWords.map(RegExp.escape).join('|');
    final danglingLink = RegExp('(^|\\s)($link)(?=\\s*([,:;]|\$))', caseSensitive: false);
    final leadingLink = RegExp('^($link)\\s+', caseSensitive: false);
    var text = kept.join().replaceAll(RegExp(r'\s+'), ' ');
    for (var i = 0; i < 3; i++) {
      text = text
          .replaceAllMapped(RegExp(r'([,;])(\s*[,;:])+'), (m) => m.group(1)!)
          .replaceAllMapped(danglingLink, (m) => m.group(1)!)
          .replaceFirst(leadingLink, '')
          .replaceAll(RegExp(r'^[\s,:;]+|[\s,:;]+$'), '')
          .replaceAll(RegExp(r'\s+,'), ',')
          .replaceAll(RegExp(r'\s{2,}'), ' ');
    }
    if (text.isEmpty) return '';
    return text[0].toUpperCase() + text.substring(1);
  }

  /// The label of group [g] in [lang], as written for the screen.
  String _label(Object g, String lang) {
    final known = _displayLabels[localizedText(g, 'fr').trim().toLowerCase()];
    return (known?[lang] ?? known?['fr'] ?? localizedText(g, lang)).trim();
  }

  /// What the user sees, in [lang]: every group, each word written only
  /// once in the whole list. A word already shown above is taken out of the
  /// label; a label left empty is not shown. Each item keeps its index in
  /// [groups], so saved days stay valid.
  List<(int, String)> shown(String lang) {
    final seen = <String>[];
    final result = <(int, String)>[];
    final all = groups;
    for (var i = 0; i < all.length; i++) {
      final label = _withoutRepeats(_label(all[i], lang), seen);
      if (label.isNotEmpty) result.add((i, label));
    }
    return result;
  }

  int get minimum => asInt(config.alimentationFemme['diversite_minimale_groupes']) ?? 5;

  bool met(Set<int> eaten) => eaten.length >= minimum;

  /// The ticked groups among those shown in [lang] (a hidden one never counts).
  Set<int> eatenShown(Set<int> eaten, String lang) => {
    for (final (i, _) in shown(lang))
      if (eaten.contains(i)) i,
  };

  /// Diversity reached with the groups shown in [lang]; never more than they allow.
  bool metShown(Set<int> eaten, String lang) {
    final visible = shown(lang).length;
    return eatenShown(eaten, lang).length >= (minimum < visible ? minimum : visible);
  }
}
