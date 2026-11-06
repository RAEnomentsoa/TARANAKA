import '../providers/language_provider.dart';
import '../services/cycle_timeline.dart';

extension LocalizedText on AppLanguage {
  String pick({required String mg, required String fr}) => switch (this) {
    AppLanguage.mg => mg,
    AppLanguage.fr => fr,
  };

  /// Nom du mois [month] (de 1 à 12).
  String monthName(int month) => switch (this) {
    AppLanguage.mg => const [
      'Janoary',
      'Febroary',
      'Martsa',
      'Aprily',
      'Mey',
      'Jona',
      'Jolay',
      'Aogositra',
      'Septambra',
      'Oktobra',
      'Novambra',
      'Desambra',
    ],
    AppLanguage.fr => const [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ],
  }[month - 1];

  /// Abréviation du jour [weekday] (`DateTime.monday` à `DateTime.sunday`).
  String weekdayShort(int weekday) => switch (this) {
    AppLanguage.mg => const ['Alt', 'Tal', 'Alr', 'Alk', 'Zom', 'Asa', 'Alh'],
    AppLanguage.fr => const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'],
  }[weekday - 1];

  String formatDate(DateTime date) =>
      '${date.day} ${monthName(date.month)} ${date.year}';

  String formatDays(int days) =>
      pick(mg: '$days andro', fr: days > 1 ? '$days jours' : '$days jour');

  String get expectedPeriodName =>
      pick(mg: 'Fadimbolana andrasana', fr: 'Prochaines règles attendues');

  String phaseName(CyclePhase phase) => switch (phase) {
    CyclePhase.menstruation => pick(mg: 'Fadimbolana', fr: 'Règles'),
    CyclePhase.follicular => pick(
      mg: 'Aorian’ny fadimbolana',
      fr: 'Phase folliculaire',
    ),
    CyclePhase.ovulation => pick(
      mg: 'Fotoam-pahavokarana',
      fr: 'Fenêtre d’ovulation',
    ),
    CyclePhase.luteal => pick(mg: 'Alohan’ny fadimbolana', fr: 'Phase lutéale'),
  };

  String regularityName(CycleRegularity regularity) => switch (regularity) {
    CycleRegularity.unknown => pick(
      mg: 'Mbola tsy ampy ny daty voarakitra',
      fr: 'Pas encore assez de données',
    ),
    CycleRegularity.regular => pick(mg: 'Mitovitovy', fr: 'Régulier'),
    CycleRegularity.irregular => pick(mg: 'Miovaova', fr: 'Irrégulier'),
  };

  /// Libellé d'un niveau de la colonne `intensite` (de 1 à 5) ; la valeur
  /// elle-même si elle est inconnue.
  String intensityName(String level) => switch (level) {
    '1' => pick(mg: 'Kely dia kely', fr: 'Très léger'),
    '2' => pick(mg: 'Kely', fr: 'Léger'),
    '3' => pick(mg: 'Antonony', fr: 'Moyen'),
    '4' => pick(mg: 'Be', fr: 'Abondant'),
    '5' => pick(mg: 'Be dia be', fr: 'Très abondant'),
    _ => level,
  };

  /// Libellé d'une entrée de la colonne `symptome` ; l'entrée elle-même s'il
  /// s'agit de texte libre.
  String symptomName(String entry) => switch (entry) {
    PeriodSymptom.abdominalPain => pick(
      mg: 'Fanaintainan-kibo',
      fr: 'Douleurs abdominales',
    ),
    PeriodSymptom.headache => pick(mg: 'Aretin-doha', fr: 'Maux de tête'),
    PeriodSymptom.fatigue => pick(mg: 'Havizanana', fr: 'Fatigue'),
    PeriodSymptom.moodSwings => pick(
      mg: 'Fiovaovan’ny toe-po',
      fr: 'Sautes d’humeur',
    ),
    PeriodSymptom.cramps => pick(mg: 'Fihenjanan’ny kibo', fr: 'Crampes'),
    _ => entry,
  };
}

/// Colonne `intensite` : le niveau de 1 (très léger) à 5 (très abondant), en
/// texte.
abstract final class PeriodIntensity {
  static const List<int> levels = [1, 2, 3, 4, 5];

  static int? decode(String? column) {
    final level = int.tryParse(column ?? '');
    return levels.contains(level) ? level : null;
  }

  static String? encode(int? level) => level?.toString();
}

/// Colonne `symptome` : codes des suggestions et texte libre, séparés par des
/// virgules. Les codes restent indépendants de la langue d'affichage.
abstract final class PeriodSymptom {
  static const String abdominalPain = 'douleurs_abdominales';
  static const String headache = 'maux_de_tete';
  static const String fatigue = 'fatigue';
  static const String moodSwings = 'sautes_humeur';
  static const String cramps = 'crampes';
  static const List<String> values = [
    abdominalPain,
    headache,
    fatigue,
    moodSwings,
    cramps,
  ];

  static List<String> decode(String? column) => (column ?? '')
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();

  /// `NULL` en base lorsqu'aucun symptôme n'est indiqué. Une virgule du texte
  /// libre sépare deux entrées.
  static String? encode(Iterable<String> codes, String otherText) {
    final entries = [...codes, ...decode(otherText)];
    return entries.isEmpty ? null : entries.join(',');
  }
}
