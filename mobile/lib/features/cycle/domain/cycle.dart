import '../../../core/config/clinical_config.dart';
import '../../../core/util/clock.dart';

/// One period as logged by the user (spec §4).
class Period {
  const Period({
    required this.id,
    required this.start,
    this.end,
    this.intensity = 'moyenne',
    this.pain = 0,
    this.mood,
    this.notes = '',
  });

  final String id;
  final DateTime start;

  /// Last day of bleeding (inclusive), null while ongoing.
  final DateTime? end;

  /// `faible`, `moyenne`, `forte` (server enum, 3 pictograms).
  final String intensity;

  /// 0 to 3.
  final int pain;

  /// 1 to 5 (emojis), optional.
  final int? mood;
  final String notes;

  /// Days of bleeding, start and end included.
  int? get length => end == null ? null : daysBetween(start, end!) + 1;
}

/// True when [start]–[end] shares a day with another logged period. A period
/// without end counts as its first day only.
bool periodOverlaps(List<Period> periods, DateTime start, DateTime? end, {String? exceptId}) {
  final s = dateOnly(start);
  final e = dateOnly(end ?? start);
  for (final p in periods) {
    if (p.id == exceptId) continue;
    final ps = dateOnly(p.start);
    final pe = dateOnly(p.end ?? p.start);
    if (!s.isAfter(pe) && !ps.isAfter(e)) return true;
  }
  return false;
}

enum Confidence { estimate, reliable }

enum CycleSignal {
  /// Several cycles under the short limit (21 days in the sample config).
  shortCycles,

  /// Several cycles over the long limit (35 days).
  longCycles,

  /// A period longer than the limit (7 days).
  longPeriod,

  /// Very heavy bleeding logged on the last period.
  heavyBleeding,

  /// No period for more than the limit (90 days).
  amenorrhoea,

  /// The expected period is late: suggest a pregnancy test.
  late,
}

class CycleSummary {
  const CycleSummary({
    required this.periodsLogged,
    required this.cycleLengths,
    required this.averageCycle,
    required this.averagePeriod,
    required this.regular,
    required this.nextPeriod,
    required this.ovulation,
    required this.fertileStart,
    required this.fertileEnd,
    required this.confidence,
    required this.signals,
    required this.daysLate,
  });

  final int periodsLogged;

  /// Complete cycles used for the averages (most recent last).
  final List<int> cycleLengths;
  final double? averageCycle;
  final double? averagePeriod;
  final bool? regular;
  final DateTime? nextPeriod;
  final DateTime? ovulation;
  final DateTime? fertileStart;
  final DateTime? fertileEnd;
  final Confidence confidence;
  final Set<CycleSignal> signals;
  final int daysLate;
}

/// Calculations of "Mon cycle". Every number comes from `cycle` in the
/// configuration: cycles for the average, cycles for a "fiable" prediction,
/// days of the luteal phase, fertile window, attention limits.
class CycleCalculator {
  CycleCalculator(this.config);

  final ClinicalConfig config;
  Map<String, Object?> get _c => config.cycle;
  Map<String, Object?> get _s => (_c['signaux'] as Map?)?.cast<String, Object?>() ?? const {};

  int get cyclesForAverage => asInt(_c['cycles_pour_moyenne']) ?? 6;
  int get cyclesForReliable => asInt(_c['cycles_pour_prediction_fiable']) ?? 3;
  int get ovulationBeforePeriod => asInt(_c['ovulation_avant_regles_jours']) ?? 14;
  int get fertileDaysBeforeOvulation => asInt(_c['fenetre_fertile_jours_avant_ovulation']) ?? 5;
  int? get shortCycle => asInt(_s['cycle_court_jours']);
  int? get longCycle => asInt(_s['cycle_long_jours']);
  int? get longPeriod => asInt(_s['regles_longues_jours']);
  int? get amenorrhoeaDays => asInt(_s['amenorrhee_jours']);

  CycleSummary summarise(List<Period> periods, DateTime today) {
    final sorted = [...periods]..sort((a, b) => a.start.compareTo(b.start));
    final t = dateOnly(today);
    final lengths = <int>[
      for (var i = 1; i < sorted.length; i++) daysBetween(sorted[i - 1].start, sorted[i].start),
    ];
    final recent = lengths.length > cyclesForAverage
        ? lengths.sublist(lengths.length - cyclesForAverage)
        : lengths;
    final recentPeriods = sorted.reversed
        .take(cyclesForAverage)
        .map((p) => p.length)
        .whereType<int>()
        .toList();

    double? avg(List<int> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    final averageCycle = avg(recent);

    // "Régulier": every recent cycle within the normal limits of the config.
    bool? regular;
    if (recent.isNotEmpty && shortCycle != null && longCycle != null) {
      regular = recent.every((l) => l >= shortCycle! && l <= longCycle!);
    }

    DateTime? next, ovulation, fertileStart, fertileEnd;
    if (sorted.isNotEmpty && averageCycle != null) {
      next = addDays(sorted.last.start, averageCycle.round());
      ovulation = addDays(next, -ovulationBeforePeriod);
      fertileStart = addDays(ovulation, -fertileDaysBeforeOvulation);
      fertileEnd = ovulation;
    }

    final reliable = sorted.length >= cyclesForReliable && regular == true;

    final signals = <CycleSignal>{};
    if (shortCycle != null && recent.where((l) => l < shortCycle!).length >= 2) {
      signals.add(CycleSignal.shortCycles);
    }
    if (longCycle != null && recent.where((l) => l > longCycle!).length >= 2) {
      signals.add(CycleSignal.longCycles);
    }
    if (longPeriod != null && recentPeriods.any((l) => l > longPeriod!)) {
      signals.add(CycleSignal.longPeriod);
    }
    if (sorted.isNotEmpty && sorted.last.intensity == 'forte') signals.add(CycleSignal.heavyBleeding);
    var daysLate = 0;
    if (sorted.isNotEmpty) {
      final since = daysBetween(sorted.last.start, t);
      if (amenorrhoeaDays != null && since > amenorrhoeaDays!) {
        signals.add(CycleSignal.amenorrhoea);
      } else if (next != null && t.isAfter(next)) {
        daysLate = daysBetween(next, t);
        signals.add(CycleSignal.late);
      }
    }

    return CycleSummary(
      periodsLogged: sorted.length,
      cycleLengths: recent,
      averageCycle: averageCycle,
      averagePeriod: avg(recentPeriods),
      regular: regular,
      nextPeriod: next,
      ovulation: ovulation,
      fertileStart: fertileStart,
      fertileEnd: fertileEnd,
      confidence: reliable ? Confidence.reliable : Confidence.estimate,
      signals: signals,
      daysLate: daysLate,
    );
  }

  /// The ongoing period, if the last one has no end yet and could still be
  /// going on (not longer than the long-period limit plus a margin of 3 days).
  Period? ongoing(List<Period> periods, DateTime today) {
    if (periods.isEmpty) return null;
    final last = ([...periods]..sort((a, b) => a.start.compareTo(b.start))).last;
    if (last.end != null) return null;
    return daysBetween(last.start, today) <= (longPeriod ?? 7) + 3 ? last : null;
  }
}
