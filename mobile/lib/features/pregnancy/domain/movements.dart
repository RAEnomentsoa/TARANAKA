import '../../../core/util/clock.dart';
import 'pregnancy.dart';

/// Kinds of baby movements, as the mother feels them.
enum MovementType {
  kick('coup_pied'),
  flutter('fremissement'),
  roll('roulade'),
  hiccup('hoquet'),
  stretch('etirement'),

  /// "+1 mouvement": noted in one tap, without saying what it was.
  felt('ressenti');

  const MovementType(this.code);
  final String code;

  /// Hiccups are regular little jolts, not movements of the baby: they are
  /// noted but not added to the count of movements.
  bool get counts => this != hiccup;

  /// The kinds the mother can choose (the "+1" one has its own button).
  static const choosable = [kick, flutter, roll, stretch, hiccup];

  static MovementType parse(Object? code) =>
      values.firstWhere((t) => t.code == code, orElse: () => MovementType.kick);
}

class MovementEvent {
  const MovementEvent({required this.id, required this.at, required this.type});
  final String id;
  final DateTime at;
  final MovementType type;
}

/// One day of the history: movements counted (hiccups apart) and every
/// movement noted, most recent first.
class MovementDay {
  const MovementDay({required this.date, required this.count, required this.hiccups, required this.events});

  final DateTime date;

  /// Movements felt that day (hiccups not included), with the counts of the
  /// former counter (no hour known for those).
  final int count;
  final int hiccups;
  final List<MovementEvent> events;
}

/// The whole history by day, most recent first. [counts] are the day totals
/// of the former counter; [events] the movements noted one by one.
List<MovementDay> movementHistory(Map<DateTime, int> counts, List<MovementEvent> events) {
  final byDay = <DateTime, List<MovementEvent>>{};
  for (final e in events) {
    (byDay[dateOnly(e.at)] ??= []).add(e);
  }
  final days = {...counts.keys.map(dateOnly), ...byDay.keys}.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final d in days)
      MovementDay(
        date: d,
        count: (counts[d] ?? 0) + (byDay[d] ?? const []).where((e) => e.type.counts).length,
        hiccups: (byDay[d] ?? const []).where((e) => !e.type.counts).length,
        events: (byDay[d] ?? <MovementEvent>[])..sort((a, b) => b.at.compareTo(a.at)),
      ),
  ];
}

/// What to say about the movements at this term.
enum MovementStage {
  /// Before the usual first movements (e.g. < 16 SA): nothing felt is normal.
  notYet,

  /// First movements up to 28 SA (config): irregular, note them when felt.
  early,

  /// From 28 SA: a moment each day to feel them; a change is the alert.
  daily,
}

MovementStage movementStage(PregnancyCalculator calc, GestationalAge? age) {
  final weeks = age?.weeks;
  if (weeks == null) return MovementStage.early;
  if (weeks >= calc.movementsFromWeeks) return MovementStage.daily;
  if (weeks < calc.firstMovementsWeeks.first) return MovementStage.notYet;
  return MovementStage.early;
}
