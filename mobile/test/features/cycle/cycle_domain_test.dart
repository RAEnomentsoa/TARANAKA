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
    // Fertile window: 5 days before ovulation to the day after.
    // Fertile window: the 5 days before ovulation and the day of ovulation.
    expect((s.fertileStart, s.fertileEnd), (DateTime(2026, 10, 10), DateTime(2026, 10, 15)));
    // Pregnancy still possible 3 days before and 2 days after.
    expect((s.riskStart, s.riskEnd), (DateTime(2026, 10, 7), DateTime(2026, 10, 17)));
    expect(s.confidence, Confidence.reliable);
    expect(s.signals, isEmpty);
  });

  test('a period marked irregular by the user: "irrégulier" and only an estimate', () {
    final periods = [
      p(DateTime(2026, 7, 8)),
      p(DateTime(2026, 8, 5)),
      p(DateTime(2026, 9, 3)),
      Period(
        id: 'irr',
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 5),
        symptoms: const {'crampes', 'fatigue'},
        irregular: true,
      ),
    ];
    final s = calc.summarise(periods, DateTime(2026, 10, 10));
    expect(s.regular, isFalse);
    expect(s.confidence, Confidence.estimate);
    // The prediction itself still uses the logged dates.
    expect(s.nextPeriod, DateTime(2026, 10, 29));
  });

  test('before 3 cycles: "estimation"', () {
    final s = calc.summarise([p(DateTime(2026, 9, 3)), p(DateTime(2026, 10, 1))], DateTime(2026, 10, 10));
    expect(s.confidence, Confidence.estimate);
    expect(s.nextPeriod, DateTime(2026, 10, 29));
  });

  test('first period logged today: next period at +28 days, ovulation 14 days before', () {
    final today = DateTime(2026, 11, 4);
    final s = calc.summarise([Period(id: 'first', start: today)], today);
    expect(s.averageCycle, isNull);
    expect(s.predictionCycle, 28);
    expect(s.nextPeriod, DateTime(2026, 12, 2));
    expect(s.ovulation, DateTime(2026, 11, 18)); // day 14 of the cycle
    expect((s.fertileStart, s.fertileEnd), (DateTime(2026, 11, 13), DateTime(2026, 11, 18)));
    expect((s.riskStart, s.riskEnd), (DateTime(2026, 11, 10), DateTime(2026, 11, 20)));
    expect(s.confidence, Confidence.estimate);
    expect(s.signals, isEmpty);
  });

  test('no period logged: no prediction', () {
    final s = calc.summarise(const [], DateTime(2026, 10, 10));
    expect(s.nextPeriod, isNull);
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

  test('usual period length: the setting (3 to 8 days) wins over the average', () {
    final periods = [p(DateTime(2026, 9, 3)), p(DateTime(2026, 10, 1))];
    expect(calc.summarise(periods, DateTime(2026, 10, 10)).periodDays, 5);
    expect(calc.summarise(periods, DateTime(2026, 10, 10), periodDays: 7).periodDays, 7);
    expect(usualPeriodDays(12, null), periodDaysMax);
    expect(usualPeriodDays(1, null), periodDaysMin);
  });

  test('a period whose end was forgotten lasts its usual length, never the whole month', () {
    final open = Period(id: 'f', start: DateTime(2026, 10, 1));
    // Still possibly going on: up to the usual length plus 2 days.
    expect(forgottenEnd(open, DateTime(2026, 10, 6), 5), isNull);
    expect(calc.ongoing([open], DateTime(2026, 10, 6)), isNotNull);
    // Then closed at the usual length.
    expect(forgottenEnd(open, DateTime(2026, 10, 30), 5), DateTime(2026, 10, 5));
    expect(calc.ongoing([open], DateTime(2026, 10, 30)), isNull);
    final today = DateTime(2026, 10, 30);
    final marks = calendarMarks(periods: [open], summary: calc.summarise([open], today), today: today);
    expect(marks[DateTime(2026, 10, 5)], DayMark.period);
    expect(marks[DateTime(2026, 10, 6)], isNull);
    expect(marks[DateTime(2026, 10, 25)], isNull);
    // One period logged: the next one expected 28 days after its start.
    expect(marks[DateTime(2026, 10, 29)], DayMark.predicted);
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
    expect(marks[DateTime(2026, 10, 14)], DayMark.fertile);
    expect(marks[DateTime(2026, 10, 16)], DayMark.risk);
    expect(marks[DateTime(2026, 10, 7)], DayMark.risk);
    expect(marks[DateTime(2026, 10, 17)], DayMark.risk);
    expect(marks[DateTime(2026, 10, 18)], isNull);
    // The "Règles prévues" pictogram: on the exact computed dates only.
    final summary = calc.summarise(periods, today);
    expect(predictedStarts(summary, today).take(2), [DateTime(2026, 10, 29), DateTime(2026, 11, 26)]);
    // Following cycles too, up to 3 months ahead.
    expect(marks[DateTime(2026, 11, 26)], DayMark.predicted);
    expect(marks[DateTime(2027, 1, 21)], DayMark.predicted);
    // Nothing after January (October + 3 months).
    expect(marks.keys.where((d) => d.isAfter(DateTime(2027, 1, 31))), isEmpty);
  });

  test('calendar marks from the first period: expected period at +28 days', () {
    final today = DateTime(2026, 11, 4);
    final periods = [Period(id: 'first', start: today)];
    final summary = calc.summarise(periods, today);
    final marks = calendarMarks(periods: periods, summary: summary, today: today);
    expect(marks[today], DayMark.ongoing);
    expect(marks[DateTime(2026, 12, 2)], DayMark.predicted);
    expect(predictedStarts(summary, today).first, DateTime(2026, 12, 2));
    expect(marks[DateTime(2026, 11, 18)], DayMark.ovulation);
    expect(marks[DateTime(2026, 11, 13)], DayMark.fertile);
    expect(marks[DateTime(2026, 11, 10)], DayMark.risk);
  });

  test('calendar marks without any period: nothing', () {
    final today = DateTime(2026, 10, 2);
    expect(calendarMarks(periods: const [], summary: calc.summarise(const [], today), today: today), isEmpty);
  });
}
