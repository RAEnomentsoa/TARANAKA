import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../domain/cycle.dart';

enum DayMark { period, predicted, fertile, ovulation }

/// Two months, with a pictogram in each marked day (never colour alone).
class CycleCalendar extends StatelessWidget {
  const CycleCalendar({super.key, required this.periods, required this.summary, required this.today});

  final List<Period> periods;
  final CycleSummary summary;
  final DateTime today;

  Map<DateTime, DayMark> _marks() {
    final marks = <DateTime, DayMark>{};
    final s = summary;
    if (s.fertileStart != null) {
      for (var d = s.fertileStart!; !d.isAfter(s.fertileEnd!); d = addDays(d, 1)) {
        marks[d] = DayMark.fertile;
      }
      marks[s.ovulation!] = DayMark.ovulation;
    }
    if (s.nextPeriod != null) {
      final days = (s.averagePeriod ?? 5).round();
      for (var i = 0; i < days; i++) {
        marks[addDays(s.nextPeriod!, i)] = DayMark.predicted;
      }
    }
    for (final p in periods) {
      final end = p.end ?? (p.start.isAfter(today) ? p.start : dateOnly(today));
      for (var d = p.start; !d.isAfter(end); d = addDays(d, 1)) {
        marks[d] = DayMark.period;
      }
    }
    return marks;
  }

  static IconData icon(DayMark m) => switch (m) {
    DayMark.period => Icons.water_drop,
    DayMark.predicted => Icons.water_drop_outlined,
    DayMark.fertile => Icons.spa_outlined,
    DayMark.ovulation => Icons.star,
  };

  static Color color(DayMark m) => switch (m) {
    DayMark.period => AppColors.danger,
    DayMark.predicted => AppColors.danger,
    DayMark.fertile => AppColors.accent,
    DayMark.ovulation => AppColors.accent,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final marks = _marks();
    // From the month of the current fertile window (it can be just before
    // today) to the month after today.
    final current = DateTime(today.year, today.month);
    final fertile = summary.fertileStart;
    final first = fertile != null && fertile.isBefore(current)
        ? DateTime(fertile.year, fertile.month)
        : current;
    final months = [
      for (
        var m = first;
        !m.isAfter(DateTime(current.year, current.month + 1));
        m = DateTime(m.year, m.month + 1)
      )
        m,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final month in months) ...[
          _Month(month: month, marks: marks, today: dateOnly(today)),
          const SizedBox(height: Space.m),
        ],
        Wrap(
          spacing: Space.l,
          runSpacing: Space.s,
          children: [
            for (final (m, label) in [
              (DayMark.period, l10n.calendarLegendPeriod),
              (DayMark.predicted, l10n.calendarLegendPredicted),
              (DayMark.fertile, l10n.calendarLegendFertile),
              (DayMark.ovulation, l10n.calendarLegendOvulation),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon(m), size: 18, color: color(m)),
                  const SizedBox(width: Space.xs),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({required this.month, required this.marks, required this.today});

  final DateTime month;
  final Map<DateTime, DayMark> marks;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final offset = (DateTime(month.year, month.month).weekday - 1) % 7; // Monday first
    final cells = <Widget>[
      for (var i = 0; i < offset; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _Day(
          date: DateTime(month.year, month.month, d),
          mark: marks[DateTime(month.year, month.month, d)],
          today: today,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${month.month.toString().padLeft(2, '0')}/${month.year}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: Space.xs),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.9,
          children: cells,
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.date, required this.mark, required this.today});

  final DateTime date;
  final DayMark? mark;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final isToday = date == today;
    final m = mark;
    return Container(
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: m == DayMark.period
            ? AppColors.dangerSoft
            : (m == DayMark.fertile || m == DayMark.ovulation ? AppColors.accentSoft : null),
        borderRadius: BorderRadius.circular(Radii.s),
        border: isToday ? Border.all(color: AppColors.text, width: 1.5) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.day}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontWeight: isToday ? FontWeight.w800 : null),
          ),
          if (m != null) Icon(CycleCalendar.icon(m), size: 12, color: CycleCalendar.color(m)),
        ],
      ),
    );
  }
}
