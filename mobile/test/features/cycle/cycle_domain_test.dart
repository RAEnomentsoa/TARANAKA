import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/features/cycle/domain/cycle.dart';
import 'package:taranaka/features/cycle/presentation/cycle_calendar.dart';

import '../../helpers/config_fixture.dart';

void main() {
  final calc = CycleCalculator(sampleConfig());
  var n = 0;
  Period p(DateTime start, {int days = 5, String intensity = 'moyenne'}) => Period(
    id: '${n++}',
    start: start,
    end: start.add(Duration(days: days - 1)),
    intensity: intensity,
  );

  test('scenario 2: 3 cycles of 28, 29, 28 days → next period, fertile window, "fiable"', () {
    final periods = [
      p(DateTime(2026, 7, 8)),
      p(DateTime(2026, 8, 5)), // 28
      p(DateTime(2026, 9, 3)), // 29
      p(DateTime(2026, 10, 1)), // 28
    ];
    final s = calc.summarise(periods, DateTime(2026, 10, 10));
    expect(s.cycleLengths, [28, 29, 28]);
    expect(s.averageCycle, closeTo(28.33, 0.01));
    expect(s.averagePeriod, 5);
    expect(s.regular, isTrue);
    expect(s.nextPeriod, DateTime(2026, 10, 29));
    expect(s.ovulation, DateTime(2026, 10, 15));
    expect((s.fertileStart, s.fertileEnd), (DateTime(2026, 10, 10), DateTime(2026, 10, 15)));
    expect(s.confidence, Confidence.reliable);
    expect(s.signals, isEmpty);
  });

  test('before 3 cycles: "estimation"', () {
    final s = calc.summarise([p(DateTime(2026, 9, 3)), p(DateTime(2026, 10, 1))], DateTime(2026, 10, 10));
    expect(s.confidence, Confidence.estimate);
    expect(s.nextPeriod, DateTime(2026, 10, 29));
  });

  test('one period only: no prediction yet', () {
    final s = calc.summarise([p(DateTime(2026, 10, 1))], DateTime(2026, 10, 10));
    expect(s.nextPeriod, isNull);
    expect(s.confidence, Confidence.estimate);
  });

  test('irregular cycles stay an "estimation"', () {
    final periods = [
      p(DateTime(2026, 5, 1)),
      p(DateTime(2026, 6, 15)),
      p(DateTime(2026, 7, 10)),
      p(DateTime(2026, 8, 5)),
    ];
    final s = calc.summarise(periods, DateTime(2026, 8, 10));
    expect(s.regular, isFalse);
    expect(s.confidence, Confidence.estimate);
  });

  test('average over the last 6 cycles only', () {
    final starts = [
      for (var i = 0; i < 9; i++) DateTime(2026, 1, 1).add(Duration(days: i * (i < 3 ? 40 : 28))),
    ];
    final s = calc.summarise([for (final d in starts) p(d)], starts.last.add(const Duration(days: 3)));
    expect(s.cycleLengths.length, 6);
  });

  test('signals: repeated short or long cycles (2 or more), not a single one', () {
    final once = [
      p(DateTime(2026, 6, 1)),
      p(DateTime(2026, 6, 19)),
      p(DateTime(2026, 7, 17)),
      p(DateTime(2026, 8, 14)),
    ];
    expect(calc.summarise(once, DateTime(2026, 8, 20)).signals, isNot(contains(CycleSignal.shortCycles)));
    final twice = [
      p(DateTime(2026, 6, 1)),
      p(DateTime(2026, 6, 19)),
      p(DateTime(2026, 7, 7)),
      p(DateTime(2026, 8, 4)),
    ];
    expect(calc.summarise(twice, DateTime(2026, 8, 10)).signals, contains(CycleSignal.shortCycles));
    final long = [
      p(DateTime(2026, 3, 1)),
      p(DateTime(2026, 4, 10)),
      p(DateTime(2026, 5, 20)),
      p(DateTime(2026, 6, 20)),
    ];
    expect(calc.summarise(long, DateTime(2026, 6, 25)).signals, contains(CycleSignal.longCycles));
  });

  test('signals: period longer than 7 days, very heavy bleeding', () {
    final s = calc.summarise([
      p(DateTime(2026, 9, 3)),
      p(DateTime(2026, 10, 1), days: 8, intensity: 'forte'),
    ], DateTime(2026, 10, 10));
    expect(s.signals, containsAll([CycleSignal.longPeriod, CycleSignal.heavyBleeding]));
    final seven = calc.summarise([p(DateTime(2026, 10, 1), days: 7)], DateTime(2026, 10, 10));
    expect(seven.signals, isNot(contains(CycleSignal.longPeriod)));
  });

  test('late period suggests a pregnancy test; over 90 days is amenorrhoea', () {
    final periods = [p(DateTime(2026, 8, 5)), p(DateTime(2026, 9, 2)), p(DateTime(2026, 9, 30))];
    final late = calc.summarise(periods, DateTime(2026, 11, 2));
    expect(late.signals, contains(CycleSignal.late));
    expect(late.daysLate, 5);
    final amenorrhoea = calc.summarise(periods, DateTime(2027, 1, 5));
    expect(amenorrhoea.signals, contains(CycleSignal.amenorrhoea));
    expect(amenorrhoea.signals, isNot(contains(CycleSignal.late)));
  });

  test('ongoing period: last one without an end, recent', () {
    final open = Period(id: 'x', start: DateTime(2026, 11, 2));
    expect(calc.ongoing([open], DateTime(2026, 11, 4)), isNotNull);
    expect(calc.ongoing([open], DateTime(2026, 11, 20)), isNull);
    expect(calc.ongoing([p(DateTime(2026, 11, 1))], DateTime(2026, 11, 4)), isNull);
  });

  test('parameters come from the configuration', () {
    expect((calc.cyclesForAverage, calc.cyclesForReliable), (6, 3));
    expect((calc.ovulationBeforePeriod, calc.fertileDaysBeforeOvulation), (14, 5));
    expect((calc.shortCycle, calc.longCycle, calc.longPeriod, calc.amenorrhoeaDays), (21, 35, 7, 90));
  });

  test('calendar marks: logged, ongoing, expected days, next cycles at the average length', () {
    final periods = [
      p(DateTime(2026, 7, 8)),
      p(DateTime(2026, 8, 5)),
      p(DateTime(2026, 9, 3)),
      Period(id: 'now', start: DateTime(2026, 10, 1)),
    ];
    final today = DateTime(2026, 10, 2);
    final marks = calendarMarks(periods: periods, summary: calc.summarise(periods, today), today: today);
    expect(marks[DateTime(2026, 9, 3)], DayMark.period);
    expect(marks[DateTime(2026, 9, 7)], DayMark.period);
    expect(marks[DateTime(2026, 9, 8)], isNull);
    expect(marks[DateTime(2026, 10, 1)], DayMark.ongoing);
    expect(marks[DateTime(2026, 10, 2)], DayMark.ongoing);
    // The ongoing period is expected to last the usual 5 days.
    expect(marks[DateTime(2026, 10, 3)], DayMark.predicted);
    expect(marks[DateTime(2026, 10, 5)], DayMark.predicted);
    expect(marks[DateTime(2026, 10, 6)], isNull);
    // Next period 29 Oct (28-day average), ovulation 14 days before.
    expect(marks[DateTime(2026, 10, 29)], DayMark.predicted);
    expect(marks[DateTime(2026, 10, 15)], DayMark.ovulation);
    expect(marks[DateTime(2026, 10, 10)], DayMark.fertile);
    // Following cycles too, up to 3 months ahead.
    expect(marks[DateTime(2026, 11, 26)], DayMark.predicted);
    expect(marks[DateTime(2027, 1, 21)], DayMark.predicted);
    // Nothing after January (October + 3 months).
    expect(marks.keys.where((d) => d.isAfter(DateTime(2027, 1, 31))), isEmpty);
  });

  test('calendar marks without any prediction: only logged days', () {
    final periods = [p(DateTime(2026, 9, 3))];
    final today = DateTime(2026, 10, 2);
    final marks = calendarMarks(periods: periods, summary: calc.summarise(periods, today), today: today);
    expect(marks.values.toSet(), {DayMark.period});
    expect(marks, hasLength(5));
  });
}
