import '../models/cycle.dart';
import 'days.dart';

enum CyclePhase { menstruation, follicular, ovulation, luteal }

enum CycleRegularity { unknown, regular, irregular }

abstract final class CycleRules {
  static const int defaultCycleLength = 28;
  static const int defaultPeriodLength = 5;

  /// Un écart hors de ces bornes reflète plutôt un cycle oublié ou une grossesse
  /// qu'une vraie durée : il est conservé mais n'entre pas dans la moyenne.
  static const int minPlausibleLength = 15;
  static const int maxPlausibleLength = 60;

  static const int minPeriodLength = 1;
  static const int maxPeriodLength = 15;

  /// Durée de la phase lutéale : l'ovulation précède les règles de 14 jours.
  static const int lutealLength = 14;
  static const int windowDaysBeforeOvulation = 5;
  static const int windowDaysAfterOvulation = 1;

  /// Écart maximal entre le plus court et le plus long cycle d'un profil régulier.
  static const int regularSpread = 7;

  /// Nombre de cycles futurs projetés sur le calendrier.
  static const int forecastCycles = 3;

  static bool isPlausibleLength(int days) =>
      days >= minPlausibleLength && days <= maxPlausibleLength;

  static bool isPlausiblePeriod(int days) =>
      days >= minPeriodLength && days <= maxPeriodLength;
}

/// Phase du jour [day] (à partir de 1) d'un cycle. Les règles priment sur la
/// fenêtre d'ovulation, qui peut les chevaucher sur un cycle très court.
CyclePhase phaseOfDay(int day, int cycleLength, int periodLength) {
  if (day <= periodLength) return CyclePhase.menstruation;
  final ovulationDay = cycleLength - CycleRules.lutealLength;
  if (day < ovulationDay - CycleRules.windowDaysBeforeOvulation) {
    return CyclePhase.follicular;
  }
  if (day <= ovulationDay + CycleRules.windowDaysAfterOvulation) {
    return CyclePhase.ovulation;
  }
  return CyclePhase.luteal;
}

/// Phase d'un jour du calendrier. [forecast] signale un jour encore à venir ou
/// projeté au-delà du dernier cycle.
typedef DayMark = ({CyclePhase phase, bool forecast});

/// Calculs dérivés de l'historique.
///
/// Les dates de début peuvent être à venir : le cycle « en cours » à une date
/// est donc le dernier commencé à cette date, pas forcément la dernière ligne.
class CycleTimeline {
  CycleTimeline(Iterable<Cycle> rows)
    : cycles = rows.where((c) => parseDay(c.dateDebut) != null).toList()
        ..sort(
          (a, b) => parseDay(a.dateDebut)!.compareTo(parseDay(b.dateDebut)!),
        );

  /// Du plus ancien au plus récent.
  final List<Cycle> cycles;

  bool get isEmpty => cycles.isEmpty;

  int get _lastIndex => cycles.length - 1;

  DateTime _start(int index) => parseDay(cycles[index].dateDebut)!;

  /// Dernier cycle commencé à [day], -1 s'il n'y en a aucun.
  int _indexOn(DateTime day) =>
      cycles.lastIndexWhere((c) => !parseDay(c.dateDebut)!.isAfter(day));

  /// Durée réelle de chaque cycle terminé.
  late final List<int> elapsedLengths = [
    for (var i = 0; i < _lastIndex; i++) daysBetween(_start(i), _start(i + 1)),
  ];

  late final List<int> _plausibleLengths = elapsedLengths
      .where(CycleRules.isPlausibleLength)
      .toList();

  int? get _declaredLength {
    final declared = isEmpty ? null : cycles.last.dureCycle;
    return declared != null && CycleRules.isPlausibleLength(declared)
        ? declared
        : null;
  }

  /// Moyenne des cycles réels, sinon la durée déclarée, sinon 28 jours.
  late final int averageLength = _plausibleLengths.isNotEmpty
      ? _mean(_plausibleLengths)
      : _declaredLength ?? CycleRules.defaultCycleLength;

  /// Durée retenue pour le dernier cycle : celle que l'utilisatrice a saisie
  /// pour ce cycle, sinon la moyenne.
  int get predictedLength => _declaredLength ?? averageLength;

  late final int averagePeriodLength = isEmpty
      ? CycleRules.defaultPeriodLength
      : _mean(cycles.map(_periodLengthOf).toList());

  CycleRegularity get regularity {
    if (_plausibleLengths.length < 2) return CycleRegularity.unknown;
    final sorted = [..._plausibleLengths]..sort();
    return sorted.last - sorted.first <= CycleRules.regularSpread
        ? CycleRegularity.regular
        : CycleRegularity.irregular;
  }

  /// Valeur de `estimationProchain` : début du dernier cycle + durée retenue.
  DateTime? get nextStart =>
      isEmpty ? null : addDays(_start(_lastIndex), predictedLength);

  /// Prochain début après [today] : une date déjà saisie, sinon l'estimation.
  DateTime? nextStartOn(DateTime today) {
    if (isEmpty) return null;
    final index = _indexOn(today);
    return index < _lastIndex ? _start(index + 1) : nextStart;
  }

  DateTime? ovulationBefore(DateTime? start) =>
      start == null ? null : addDays(start, -CycleRules.lutealLength);

  /// Date estimée à signaler sur le calendrier, telle qu'enregistrée.
  DateTime? get storedEstimate =>
      isEmpty ? null : parseDay(cycles.last.estimationProchain) ?? nextStart;

  /// Jour du cycle en cours à [today], à partir de 1 ; `null` si aucun cycle
  /// n'a encore commencé.
  int? cycleDayOn(DateTime today) {
    final index = _indexOn(today);
    return index < 0 ? null : daysBetween(_start(index), today) + 1;
  }

  /// Début du premier cycle saisi, si tous sont encore à venir.
  DateTime? upcomingStartOn(DateTime today) =>
      !isEmpty && _indexOn(today) < 0 ? _start(0) : null;

  /// Jours de retard : seul le dernier cycle peut en avoir, les autres ayant
  /// déjà un cycle suivant.
  int lateDaysOn(DateTime today) {
    if (isEmpty || _indexOn(today) != _lastIndex) return 0;
    final day = cycleDayOn(today)!;
    return day <= predictedLength ? 0 : day - predictedLength;
  }

  int _lengthAt(int index) {
    if (index == _lastIndex) return predictedLength;
    final length = elapsedLengths[index];
    return CycleRules.isPlausibleLength(length) ? length : averageLength;
  }

  /// Jours du cycle affiché sur la roue : celui en cours à [today], ou le
  /// premier à venir.
  List<(DateTime, CyclePhase)> currentCycleDays(DateTime today) {
    if (isEmpty) return const [];
    final index = _indexOn(today) < 0 ? 0 : _indexOn(today);
    final length = _lengthAt(index);
    final periodLength = _periodLengthOf(cycles[index]);
    return [
      for (var i = 0; i < length; i++)
        (addDays(_start(index), i), phaseOfDay(i + 1, length, periodLength)),
    ];
  }

  /// Phase de [date], ou `null` si elle est inconnue : avant le premier cycle,
  /// au-delà des prévisions, ou hors des règles d'un écart non plausible.
  DayMark? markOn(DateTime date, DateTime today) {
    final index = _indexOn(date);
    if (index < 0) return null;
    final day = daysBetween(_start(index), date) + 1;
    final periodLength = _periodLengthOf(cycles[index]);
    final isFuture = date.isAfter(today);

    if (index < _lastIndex) {
      final length = elapsedLengths[index];
      if (day <= periodLength) {
        return (phase: CyclePhase.menstruation, forecast: isFuture);
      }
      if (!CycleRules.isPlausibleLength(length)) return null;
      return (phase: phaseOfDay(day, length, periodLength), forecast: isFuture);
    }

    final length = predictedLength;
    if (day <= length) {
      return (phase: phaseOfDay(day, length, periodLength), forecast: isFuture);
    }
    final projectedCycle = (day - 1) ~/ length;
    if (projectedCycle > CycleRules.forecastCycles) return null;
    return (
      phase: phaseOfDay((day - 1) % length + 1, length, averagePeriodLength),
      forecast: true,
    );
  }

  /// [row], qui doit appartenir à [cycles], avec ses colonnes calculées :
  /// - `dure_cycle` : durée réelle si le cycle est terminé. Sur le dernier, la
  ///   valeur saisie est gardée, `NULL` compris ;
  /// - `dure_regle` : valeur saisie, sinon d'après `date_fin`, sinon 5 jours ;
  /// - `estimationProchain` : recalculée sur le dernier cycle. Un cycle terminé
  ///   garde la prévision faite à l'époque.
  Cycle computed(Cycle row) {
    final index = cycles.indexOf(row);
    final isLast = index == _lastIndex;
    return row.withComputed(
      dureCycle: isLast ? row.dureCycle : elapsedLengths[index],
      dureRegle: _periodLengthOf(row),
      estimationProchain: isLast
          ? formatDay(nextStart!)
          : row.estimationProchain,
    );
  }

  /// Lignes dont les colonnes calculées ne correspondent plus aux dates, avec
  /// leurs nouvelles valeurs.
  List<Cycle> outdatedRows() {
    final outdated = <Cycle>[];
    for (final row in cycles) {
      final updated = computed(row);
      if (updated.dureCycle != row.dureCycle ||
          updated.dureRegle != row.dureRegle ||
          updated.estimationProchain != row.estimationProchain) {
        outdated.add(updated);
      }
    }
    return outdated;
  }

  int _periodLengthOf(Cycle cycle) {
    final stored = cycle.dureRegle;
    if (stored != null && stored >= 1) return stored;
    final end = parseDay(cycle.dateFin);
    final fromDates = end == null
        ? 0
        : daysBetween(parseDay(cycle.dateDebut)!, end) + 1;
    return fromDates >= 1 ? fromDates : CycleRules.defaultPeriodLength;
  }

  static int _mean(List<int> values) =>
      (values.reduce((a, b) => a + b) / values.length).round();
}
