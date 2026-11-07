import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/screen.dart';
import '../domain/cycle.dart';

enum DayMark { period, ongoing, predicted, fertile, ovulation }

/// How many months the calendar shows after the current one (predictions).
const int calendarMonthsAhead = 3;

/// Marks of every day: logged periods (past cycles), the ongoing one, and the
/// predictions (next periods, fertile window, ovulation). A logged day always
/// wins over a prediction.
Map<DateTime, DayMark> calendarMarks({
  required List<Period> periods,
  required CycleSummary summary,
  required DateTime today,
}) {
  final t = dateOnly(today);
  final marks = <DateTime, DayMark>{};
  final periodDays = (summary.averagePeriod ?? 5).round().clamp(1, 10);
  final next = summary.nextPeriod;
  final average = summary.averageCycle?.round();
  if (next != null && average != null && average > 0) {
    final horizon = DateTime(t.year, t.month + calendarMonthsAhead + 1);
    final ovulationOffset = daysBetween(summary.ovulation!, next);
    final fertileOffset = daysBetween(summary.fertileStart!, next);
    // The next period, then the following ones at the average cycle length.
    for (var start = next; start.isBefore(horizon); start = addDays(start, average)) {
      for (
        var d = addDays(start, -fertileOffset);
        !d.isAfter(addDays(start, -ovulationOffset));
        d = addDays(d, 1)
      ) {
        marks[d] = DayMark.fertile;
      }
      marks[addDays(start, -ovulationOffset)] = DayMark.ovulation;
      for (var i = 0; i < periodDays; i++) {
        marks[addDays(start, i)] = DayMark.predicted;
      }
    }
  }
  for (final p in periods) {
    final start = dateOnly(p.start);
    if (p.end == null) {
      // Ongoing: logged up to today, expected for the usual length after.
      final last = start.isAfter(t) ? start : t;
      for (var d = start; !d.isAfter(last); d = addDays(d, 1)) {
        marks[d] = DayMark.ongoing;
      }
      for (var d = addDays(last, 1); daysBetween(start, d) < periodDays; d = addDays(d, 1)) {
        marks.putIfAbsent(d, () => DayMark.predicted);
      }
    } else {
      for (var d = start; !d.isAfter(dateOnly(p.end!)); d = addDays(d, 1)) {
        marks[d] = DayMark.period;
      }
    }
  }
  return marks;
}

/// Month grid of "Mon cycle": past, ongoing and expected periods, one month at
/// a time, back to the first cycle logged. Each marked day has a pictogram,
/// never colour alone. Tapping a logged period edits it; tapping another past
/// day adds a period starting that day.
class CycleCalendar extends StatefulWidget {
  const CycleCalendar({
    super.key,
    required this.periods,
    required this.summary,
    required this.today,
    required this.first,
    required this.onPeriodTap,
    required this.onDayTap,
  });

  final List<Period> periods;
  final CycleSummary summary;
  final DateTime today;

  /// Earliest day that can be logged: the calendar does not go before its month.
  final DateTime first;
  final ValueChanged<Period> onPeriodTap;
  final ValueChanged<DateTime> onDayTap;

  @override
  State<CycleCalendar> createState() => _CycleCalendarState();

  static IconData icon(DayMark m) => switch (m) {
    DayMark.period || DayMark.ongoing => Icons.water_drop,
    DayMark.predicted => Icons.water_drop_outlined,
    DayMark.fertile => Icons.spa_outlined,
    DayMark.ovulation => Icons.star,
  };

  static String label(AppLocalizations l10n, DayMark m) => switch (m) {
    DayMark.period => l10n.calendarLegendPeriod,
    DayMark.ongoing => l10n.calendarLegendOngoing,
    DayMark.predicted => l10n.calendarLegendPredicted,
    DayMark.fertile => l10n.calendarLegendFertile,
    DayMark.ovulation => l10n.calendarLegendOvulation,
  };
}

class _CycleCalendarState extends State<CycleCalendar> {
  late DateTime _month = _monthOf(widget.today);

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  DateTime get _firstMonth {
    final starts = widget.periods.map((p) => p.start);
    final earliest = starts.isEmpty ? widget.first : starts.reduce((a, b) => a.isBefore(b) ? a : b);
    return _monthOf(earliest.isBefore(widget.first) ? earliest : widget.first);
  }

  DateTime get _lastMonth => DateTime(widget.today.year, widget.today.month + calendarMonthsAhead);

  bool get _canPrev => _month.isAfter(_firstMonth);
  bool get _canNext => _month.isBefore(_lastMonth);

  void _go(int months) {
    final target = DateTime(_month.year, _month.month + months);
    if (target.isBefore(_firstMonth) || target.isAfter(_lastMonth)) return;
    setState(() => _month = target);
  }

  Period? _periodOn(DateTime day) {
    for (final p in widget.periods) {
      final end = p.end ?? (p.start.isAfter(widget.today) ? p.start : dateOnly(widget.today));
      if (!day.isBefore(dateOnly(p.start)) && !day.isAfter(dateOnly(end))) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final marks = calendarMarks(periods: widget.periods, summary: widget.summary, today: widget.today);
    final today = dateOnly(widget.today);
    final monthName = l10n.monthNames.split('|')[_month.month - 1];
    final title = '${monthName[0].toUpperCase()}${monthName.substring(1)} ${_month.year}';
    final weekdays = l10n.weekdayShort.split('|');
    final isCurrent = _month == _monthOf(today);

    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = DateTime(_month.year, _month.month).weekday - 1; // Monday first
    final rows = ((offset + days) / 7).ceil();
    final cellHeight = math.max(Space.touch, 40 * MediaQuery.textScalerOf(context).scale(1));

    Widget cell(int index) {
      final n = index - offset + 1;
      if (n < 1 || n > days) return const SizedBox.shrink();
      final date = DateTime(_month.year, _month.month, n);
      final period = _periodOn(date);
      final tappable = period != null || !date.isAfter(today);
      return _Day(
        date: date,
        mark: marks[date],
        isToday: date == today,
        height: cellHeight,
        onTap: !tappable ? null : () => period != null ? widget.onPeriodTap(period) : widget.onDayTap(date),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.m),
        child: GestureDetector(
          // Swipe left or right to change month.
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() > 200) _go(v < 0 ? 1 : -1);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('cal-prev'),
                    tooltip: l10n.calendarPrevMonth,
                    onPressed: _canPrev ? () => _go(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      key: const ValueKey('cal-month'),
                      textAlign: TextAlign.center,
                      style: text.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('cal-next'),
                    tooltip: l10n.calendarNextMonth,
                    onPressed: _canNext ? () => _go(1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              if (!isCurrent)
                Center(
                  child: TextButton(
                    key: const ValueKey('cal-today'),
                    onPressed: () => setState(() => _month = _monthOf(today)),
                    child: Text(l10n.today),
                  ),
                ),
              const Gap(Space.xs),
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (final w in weekdays)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(w, style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Gap(Space.xs),
              for (var r = 0; r < rows; r++)
                Row(children: [for (var c = 0; c < 7; c++) Expanded(child: cell(r * 7 + c))]),
              const Gap(Space.m),
              Wrap(
                spacing: Space.l,
                runSpacing: Space.s,
                children: [
                  for (final m in DayMark.values)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Swatch(mark: m),
                        const SizedBox(width: Space.xs),
                        Flexible(child: Text(CycleCalendar.label(l10n, m), style: text.bodySmall)),
                      ],
                    ),
                ],
              ),
              const Gap(Space.s),
              Text(l10n.calendarHint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

({Color? fill, Color? border, Color icon, Color text}) _style(DayMark? m) => switch (m) {
  DayMark.period => (fill: AppColors.dangerSoft, border: null, icon: AppColors.danger, text: AppColors.text),
  DayMark.ongoing => (fill: AppColors.danger, border: null, icon: AppColors.surface, text: AppColors.surface),
  DayMark.predicted => (fill: null, border: AppColors.danger, icon: AppColors.danger, text: AppColors.text),
  DayMark.fertile || DayMark.ovulation => (
    fill: AppColors.accentSoft,
    border: null,
    icon: AppColors.accent,
    text: AppColors.text,
  ),
  null => (fill: null, border: null, icon: AppColors.text, text: AppColors.text),
};

class _Swatch extends StatelessWidget {
  const _Swatch({required this.mark});
  final DayMark mark;

  @override
  Widget build(BuildContext context) {
    final s = _style(mark);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: s.fill,
        borderRadius: BorderRadius.circular(Radii.s),
        border: s.border == null ? null : Border.all(color: s.border!, width: 1.5),
      ),
      child: Icon(CycleCalendar.icon(mark), size: 14, color: s.icon),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.mark,
    required this.isToday,
    required this.height,
    required this.onTap,
  });

  final DateTime date;
  final DayMark? mark;
  final bool isToday;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = _style(mark);
    final border = isToday
        ? Border.all(color: AppColors.text, width: 2)
        : (s.border == null ? null : Border.all(color: s.border!, width: 1.5));
    final semantics = [
      formatDate(date),
      if (isToday) l10n.today,
      if (mark != null) CycleCalendar.label(l10n, mark!),
    ].join(', ');
    return Semantics(
      label: semantics,
      button: onTap != null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: s.fill ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.s),
            side: border?.top ?? BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('cal-day-${isoDate(date)}'),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(Space.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${date.day}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: onTap == null && mark == null ? AppColors.textMuted : s.text,
                          fontWeight: isToday || mark == DayMark.ongoing ? FontWeight.w800 : null,
                        ),
                      ),
                      if (mark != null)
                        Icon(CycleCalendar.icon(mark!), size: 12, color: s.icon)
                      else
                        const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
