import 'dart:math' as math;

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
    this.symptoms = const {},
    this.irregular = false,
  });

  final String id;
  final DateTime start;

  /// Last day of bleeding (inclusive), null while ongoing.
  final DateTime? end;

  /// `faible`, `moyenne`, `forte` (server enum, 3 pictograms).
  final String intensity;

  /// 0 to 3.
  final int pain;

  /// 1 to 5 (face icons, very sad to very happy), optional.
  final int? mood;
  final String notes;

  /// Codes of [periodSymptoms] felt during this period.
  final Set<String> symptoms;

  /// Marked by the user as irregular (early, late, unusual): such a cycle
  /// makes the prediction an estimate, whatever the lengths say.
  final bool irregular;

  /// Days of bleeding, start and end included.
  int? get length => end == null ? null : daysBetween(start, end!) + 1;
}

/// Bleeding intensities, lightest first (server enum, 3 pictograms).
const List<String> periodIntensities = ['faible', 'moyenne', 'forte'];

/// Small blood losses outside a real period ("spotting"): noted on a day,
/// never counted as a period nor as its flow.
const String spottingFlow = 'spotting';

/// Pain scale of the daily follow-up: 0 none, 1 light, 2 moderate, 3 strong.
const int painMax = 3;

/// Mood scale: 1 very bad to 5 very good (face icons).
const int moodMax = 5;

/// What was noted for one day in "Mon suivi du jour" (spec §4). Every field
/// is optional: only what the user chose is kept.
class DayLog {
  const DayLog({required this.day, this.flow, this.pain, this.mood, this.symptoms = const {}});

  final DateTime day;

  /// One of [periodIntensities], [spottingFlow], or null (no bleeding noted).
  final String? flow;

  /// 0 to [painMax].
  final int? pain;

  /// 1 to [moodMax].
  final int? mood;

  /// Codes of [periodSymptoms].
  final Set<String> symptoms;

  bool get isEmpty => flow == null && pain == null && mood == null && symptoms.isEmpty;
  bool get isSpotting => flow == spottingFlow;

  /// A changed copy; pass null to [flow], [pain] or [mood] to clear it.
  DayLog copyWith({
    Object? flow = _keep,
    Object? pain = _keep,
    Object? mood = _keep,
    Set<String>? symptoms,
  }) => DayLog(
    day: day,
    flow: identical(flow, _keep) ? this.flow : flow as String?,
    pain: identical(pain, _keep) ? this.pain : pain as int?,
    mood: identical(mood, _keep) ? this.mood : mood as int?,
    symptoms: symptoms ?? this.symptoms,
  );

  static const Object _keep = Object();
}

/// The period that contains [day] (an ongoing one runs until [today]).
Period? periodOn(List<Period> periods, DateTime day, DateTime today) {
  final d = dateOnly(day);
  for (final p in periods) {
    final end = dateOnly(p.end ?? today);
    if (!d.isBefore(dateOnly(p.start)) && !d.isAfter(end)) return p;
  }
  return null;
}

/// The heaviest real flow of [days] (spotting ignored), or null.
String? heaviestFlow(Iterable<DayLog> days) {
  var best = -1;
  for (final d in days) {
    best = periodIntensities.indexOf(d.flow ?? '') > best ? periodIntensities.indexOf(d.flow!) : best;
  }
  return best < 0 ? null : periodIntensities[best];
}

/// Symptoms that can be noted for a period (stored codes, never translated).
const List<String> periodSymptoms = [
  'crampes',
  'maux_de_tete',
  'fatigue',
  'ballonnements',
  'seins_sensibles',
  'mal_de_dos',
  'nausees',
  'acne',
];

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

/// Usual length of a period chosen by the user: periods generally last 3 to
/// 8 days. Without a choice, the logged average (or 5 days) is used.
const int periodDaysMin = 3;
const int periodDaysMax = 8;
const int periodDaysDefault = 5;

/// Days a period without end stays "en cours" after its usual length: past
/// them, the user forgot to note the end, and it is closed at its usual length
/// instead of running on over the whole month.
const int periodEndGraceDays = 2;

/// Usual length of a period: the user's setting, else the logged average.
int usualPeriodDays(int? setting, double? average) => setting != null
    ? setting.clamp(periodDaysMin, periodDaysMax)
    : (average?.round() ?? periodDaysDefault).clamp(1, 10);

/// End to assume for a period whose end was never noted, or null while it can
/// still be going on.
DateTime? forgottenEnd(Period p, DateTime today, int periodDays) {
  if (p.end != null) return null;
  if (daysBetween(p.start, today) < periodDays + periodEndGraceDays) return null;
  return addDays(p.start, periodDays - 1);
}

enum Confidence { estimate, reliable }

/// How much the predictions can be trusted, shown to the user in plain words:
/// low (no complete cycle yet), medium (some cycles, or irregular ones),
/// good (enough regular cycles).
enum Reliability { low, medium, good }

/// Where today falls in the cycle, for the short sentence that accompanies
/// the user ("Tu es en période fertile", "Tes règles arrivent bientôt"…).
enum CyclePhase { noData, period, late, periodSoon, ovulation, fertile, calm }

/// Days before the expected period when it is said to "arrive bientôt".
const int periodSoonDays = 3;

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
    required this.riskStart,
    required this.riskEnd,
    required this.periodDays,
    required this.predictionCycle,
    required this.confidence,
    required this.signals,
    required this.daysLate,
    this.margin = 0,
    this.cyclesToReliable = 0,
  });

  final int periodsLogged;

  /// Days of uncertainty around [nextPeriod]: the period is expected between
  /// `nextPeriod - margin` and `nextPeriod + margin`. Wide while few or
  /// irregular cycles are logged, narrow once the cycle is well known.
  final int margin;

  /// Periods still to log before the prediction can become "fiable".
  final int cyclesToReliable;

  /// Low with no complete cycle (one period or none), good when reliable,
  /// medium otherwise.
  Reliability get reliability => confidence == Confidence.reliable
      ? Reliability.good
      : cycleLengths.isEmpty
      ? Reliability.low
      : Reliability.medium;

  DateTime? get nextPeriodEarliest => nextPeriod == null ? null : addDays(nextPeriod!, -margin);
  DateTime? get nextPeriodLatest => nextPeriod == null ? null : addDays(nextPeriod!, margin);

  /// Complete cycles used for the averages (most recent last).
  final List<int> cycleLengths;
  final double? averageCycle;
  final double? averagePeriod;
  final bool? regular;
  final DateTime? nextPeriod;
  final DateTime? ovulation;
  final DateTime? fertileStart;

  /// Fertile window: the days before ovulation and ovulation itself (high
  /// probability of pregnancy).
  final DateTime? fertileEnd;

  /// Wider period where a pregnancy stays possible: a few days before and
  /// after the fertile window, at least [margin] days on each side (cycles
  /// vary, ovulation is only estimated).
  final DateTime? riskStart;
  final DateTime? riskEnd;

  /// Usual length of a period (setting or average), for the expected days.
  final int periodDays;

  /// Cycle length used for the predictions: the average of the logged
  /// cycles, else the standard cycle of 28 days (one period logged only).
  final int predictionCycle;
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

  /// Luteal phase: the days from the day after ovulation to the last day of
  /// the cycle.
  int get ovulationBeforePeriod => asInt(_c['ovulation_avant_regles_jours']) ?? 14;
  int get fertileDaysBeforeOvulation => asInt(_c['fenetre_fertile_jours_avant_ovulation']) ?? 5;

  /// Fertile window: the 5 days before ovulation and the day of ovulation
  /// (sperm live up to 5 days; the egg about one day).
  int get fertileDaysAfterOvulation => asInt(_c['fenetre_fertile_jours_apres_ovulation']) ?? 0;

  /// Standard cycle used while no complete cycle is logged (first period).
  int get defaultCycle => asInt(_c['duree_cycle_par_defaut_jours']) ?? 28;
  int get riskDaysBeforeWindow => asInt(_c['risque_jours_avant_fenetre']) ?? 3;
  int get riskDaysAfterWindow => asInt(_c['risque_jours_apres_fenetre']) ?? 2;

  /// Uncertainty of the next period while no complete cycle is logged (the
  /// standard cycle of 28 days is only a guess: cycles of 21 to 35 days are
  /// common).
  int get firstCycleMargin => asInt(_c['marge_premier_cycle_jours']) ?? 4;

  /// Widest uncertainty shown once cycles are logged.
  int get maxMargin => asInt(_c['marge_max_jours']) ?? 5;
  int? get shortCycle => asInt(_s['cycle_court_jours']);
  int? get longCycle => asInt(_s['cycle_long_jours']);
  int? get longPeriod => asInt(_s['regles_longues_jours']);
  int? get amenorrhoeaDays => asInt(_s['amenorrhee_jours']);

  /// [periodDays]: usual length of a period chosen by the user, if any.
  CycleSummary summarise(List<Period> periods, DateTime today, {int? periodDays}) {
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
    // A recent period marked irregular by the user wins over the lengths.
    if (sorted.reversed.take(cyclesForAverage).any((p) => p.irregular)) regular = false;

    // From the first period on: the average cycle, else 28 days.
    final predictionCycle = averageCycle?.round() ?? defaultCycle;
    final reliable = sorted.length >= cyclesForReliable && regular == true;

    // Uncertainty: half the spread of the recent cycles, at least 1 day once
    // reliable, 2 days otherwise; wide while no complete cycle is known.
    final int margin;
    if (recent.isEmpty) {
      margin = firstCycleMargin;
    } else {
      final spread = recent.reduce(math.max) - recent.reduce(math.min);
      margin = (spread / 2).ceil().clamp(reliable ? 1 : 2, math.max(maxMargin, 2));
    }

    DateTime? next, ovulation, fertileStart, fertileEnd, riskStart, riskEnd;
    if (sorted.isNotEmpty) {
      final cycleStart = dateOnly(sorted.last.start);
      next = addDays(cycleStart, predictionCycle);
      final cycleEnd = addDays(next, -1);
      // Every window stays inside its cycle, even a very short one.
      DateTime inCycle(DateTime d) =>
          d.isBefore(cycleStart) ? cycleStart : (d.isAfter(cycleEnd) ? cycleEnd : d);
      // Follicular phase: first day of the cycle to the day before ovulation.
      // Ovulation: day (cycle length - luteal phase), so day 14 of 28 days.
      ovulation = inCycle(addDays(cycleEnd, -ovulationBeforePeriod));
      fertileStart = inCycle(addDays(ovulation, -fertileDaysBeforeOvulation));
      fertileEnd = inCycle(addDays(ovulation, fertileDaysAfterOvulation));
      // The less predictable the cycle, the wider the days at risk.
      riskStart = inCycle(addDays(fertileStart, -math.max(riskDaysBeforeWindow, margin)));
      riskEnd = inCycle(addDays(fertileEnd, math.max(riskDaysAfterWindow, margin)));
    }

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
      riskStart: riskStart,
      riskEnd: riskEnd,
      periodDays: usualPeriodDays(periodDays, avg(recentPeriods)),
      predictionCycle: predictionCycle,
      confidence: reliable ? Confidence.reliable : Confidence.estimate,
      signals: signals,
      daysLate: daysLate,
      margin: margin,
      cyclesToReliable: math.max(0, cyclesForReliable - sorted.length),
    );
  }

  /// The ongoing period: the last one, without end, not older than its usual
  /// length plus [periodEndGraceDays] (a forgotten end never lasts a month).
  Period? ongoing(List<Period> periods, DateTime today, {int periodDays = periodDaysDefault}) {
    if (periods.isEmpty) return null;
    final last = ([...periods]..sort((a, b) => a.start.compareTo(b.start))).last;
    if (last.end != null || last.start.isAfter(dateOnly(today))) return null;
    return forgottenEnd(last, today, periodDays) == null ? last : null;
  }
}

/// Where [today] falls: the ongoing period first, then a late period, the
/// days just before the next one, ovulation, the fertile window, else calm.
CyclePhase cyclePhase(CycleSummary s, Period? ongoing, DateTime today) {
  final t = dateOnly(today);
  if (ongoing != null) return CyclePhase.period;
  final next = s.nextPeriod;
  if (next == null) return CyclePhase.noData;
  if (s.daysLate > 0 || s.signals.contains(CycleSignal.amenorrhoea)) return CyclePhase.late;
  final inDays = daysBetween(t, next);
  if (inDays >= 0 && inDays <= periodSoonDays) return CyclePhase.periodSoon;
  if (s.ovulation != null && t == dateOnly(s.ovulation!)) return CyclePhase.ovulation;
  if (s.fertileStart != null &&
      !t.isBefore(dateOnly(s.fertileStart!)) &&
      !t.isAfter(dateOnly(s.fertileEnd!))) {
    return CyclePhase.fertile;
  }
  return CyclePhase.calm;
}
