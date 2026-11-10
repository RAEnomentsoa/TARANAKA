import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/screen.dart';
import '../domain/cycle.dart';

enum DayMark { period, ongoing, predicted, risk, fertile, ovulation }

/// How many months the calendar shows after the current one (predictions).
const int calendarMonthsAhead = 3;

/// Marks of every day: logged periods (past cycles), the ongoing one, and the
/// predictions (next periods, possible risk, fertile window, ovulation). A
/// logged day always wins over a prediction. A period whose end was never
/// noted lasts its usual length, never the whole month.
Map<DateTime, DayMark> calendarMarks({
  required List<Period> periods,
  required CycleSummary summary,
  required DateTime today,
}) {
  final t = dateOnly(today);
  final marks = <DateTime, DayMark>{};
  final periodDays = summary.periodDays;
  final next = summary.nextPeriod;
  // The average cycle, or 28 days from the first period logged.
  final average = summary.predictionCycle;
  if (next != null && average > 0) {
    final horizon = DateTime(t.year, t.month + calendarMonthsAhead + 1);
    final ovulationOffset = daysBetween(summary.ovulation!, next);
    final fertileOffset = daysBetween(summary.fertileStart!, next);
    final fertileEndOffset = daysBetween(summary.fertileEnd!, next);
    final riskOffset = daysBetween(summary.riskStart!, next);
    final riskEndOffset = daysBetween(summary.riskEnd!, next);
    // The next period, then the following ones at the average cycle length.
    for (var start = next; start.isBefore(horizon); start = addDays(start, average)) {
      for (
        var d = addDays(start, -riskOffset);
        !d.isAfter(addDays(start, -riskEndOffset));
        d = addDays(d, 1)
      ) {
        marks[d] = DayMark.risk;
      }
      for (
        var d = addDays(start, -fertileOffset);
        !d.isAfter(addDays(start, -fertileEndOffset));
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
    final assumedEnd = forgottenEnd(p, t, periodDays);
    if (assumedEnd != null) {
      for (var d = start; !d.isAfter(assumedEnd); d = addDays(d, 1)) {
        marks[d] = DayMark.period;
      }
    } else if (p.end == null) {
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

/// First days of the expected periods shown in the calendar: the next one
/// (last start + cycle length, 28 days after a first period), then one every
/// cycle, up to the end of the calendar.
List<DateTime> predictedStarts(CycleSummary summary, DateTime today) {
  final next = summary.nextPeriod;
  if (next == null || summary.predictionCycle <= 0) return const [];
  final t = dateOnly(today);
  final horizon = DateTime(t.year, t.month + calendarMonthsAhead + 1);
  return [for (var d = next; d.isBefore(horizon); d = addDays(d, summary.predictionCycle)) d];
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
    DayMark.risk => Icons.error_outline,
    DayMark.fertile => Icons.spa_outlined,
    DayMark.ovulation => Icons.star,
  };

  /// Days really logged by the user, as opposed to the estimated ones.
  static bool logged(DayMark m) => m == DayMark.period || m == DayMark.ongoing;

  /// Legend under the calendar: period days, then the estimates.
  static const legend = [DayMark.period, DayMark.predicted, DayMark.fertile, DayMark.ovulation, DayMark.risk];

  static String label(AppLocalizations l10n, DayMark m) => switch (m) {
    // Logged and ongoing: one legend, "Jours des règles".
    DayMark.period || DayMark.ongoing => l10n.calendarLegendPeriodDays,
    DayMark.predicted => l10n.calendarLegendPredicted,
    DayMark.risk => l10n.calendarLegendRisk,
    DayMark.fertile => l10n.calendarLegendFertile,
    DayMark.ovulation => l10n.calendarLegendOvulation,
  };
}

class _CycleCalendarState extends State<CycleCalendar> {
  /// Always opens on the current month.
  late DateTime _month = _monthOf(widget.today);

  static DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

  @override
  void didUpdateWidget(CycleCalendar old) {
    super.didUpdateWidget(old);
    // A new day in another month (app left open overnight): back to it.
    if (_monthOf(old.today) != _monthOf(widget.today)) _month = _monthOf(widget.today);
  }

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
      final end =
          p.end ??
          forgottenEnd(p, widget.today, widget.summary.periodDays) ??
          (p.start.isAfter(widget.today) ? p.start : dateOnly(widget.today));
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
    final starts = predictedStarts(widget.summary, today).toSet();

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
        // "Règles prévues": the pictogram on the exact date computed for the
        // next periods; the other expected days only have the dashed outline.
        showIcon: marks[date] != DayMark.predicted || starts.contains(date),
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
            // A clear swipe only: a slanted page scroll never changes month.
            if (v.abs() > 600) _go(v < 0 ? 1 : -1);
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
              _LegendGroup(
                title: l10n.calendarLogged,
                marks: [
                  for (final m in CycleCalendar.legend)
                    if (CycleCalendar.logged(m)) m,
                ],
              ),
              const Gap(Space.s),
              _LegendGroup(
                title: l10n.calendarEstimated,
                marks: [
                  for (final m in CycleCalendar.legend)
                    if (!CycleCalendar.logged(m)) m,
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

/// Logged days are solid red (white drop and number); estimated days are never
/// solid: a dashed outline or a pale fill, with an outlined pictogram.
({Color? fill, Color? border, bool dashed, Color icon, Color text}) _style(DayMark? m) => switch (m) {
  DayMark.period || DayMark.ongoing => (
    fill: AppColors.danger,
    border: null,
    dashed: false,
    icon: AppColors.surface,
    text: AppColors.surface,
  ),
  DayMark.predicted => (
    fill: AppColors.surface,
    border: AppColors.danger,
    dashed: true,
    icon: AppColors.danger,
    text: AppColors.danger,
  ),
  DayMark.risk => (
    fill: AppColors.cautionSoft,
    border: null,
    dashed: false,
    icon: AppColors.caution,
    text: AppColors.text,
  ),
  DayMark.fertile || DayMark.ovulation => (
    fill: AppColors.accentSoft,
    border: null,
    dashed: false,
    icon: AppColors.accent,
    text: AppColors.text,
  ),
  null => (fill: null, border: null, dashed: false, icon: AppColors.text, text: AppColors.text),
};

/// One group of the legend: "Noté" or "Estimé", then its marks.
class _LegendGroup extends StatelessWidget {
  const _LegendGroup({required this.title, required this.marks});

  final String title;
  final List<DayMark> marks;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.labelMedium?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700),
        ),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.l,
          runSpacing: Space.s,
          children: [
            for (final m in marks)
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
      ],
    );
  }
}

/// Dashed rounded outline: the mark of an estimated period day.
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = (Offset.zero & size).deflate(0.75);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 3.5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.mark});
  final DayMark mark;

  @override
  Widget build(BuildContext context) {
    final s = _style(mark);
    return CustomPaint(
      foregroundPainter: s.dashed ? _DashedBorder(color: s.border!, radius: Radii.s) : null,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: s.fill,
          borderRadius: BorderRadius.circular(Radii.s),
          border: s.border == null || s.dashed ? null : Border.all(color: s.border!, width: 2),
        ),
        child: Icon(CycleCalendar.icon(mark), size: 14, color: s.icon),
      ),
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
    this.showIcon = true,
  });

  final DateTime date;
  final DayMark? mark;
  final bool showIcon;
  final bool isToday;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = _style(mark);
    // Today: a dark ring, over any mark (an estimated day keeps its dashes).
    final border = isToday
        ? Border.all(color: AppColors.text, width: 2)
        : (s.border == null || s.dashed ? null : Border.all(color: s.border!, width: 2));
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
        child: CustomPaint(
          foregroundPainter: s.dashed && !isToday ? _DashedBorder(color: s.border!, radius: Radii.s) : null,
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
                            fontWeight: isToday || (mark != null && CycleCalendar.logged(mark!))
                                ? FontWeight.w800
                                : null,
                          ),
                        ),
                        if (mark != null && showIcon)
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
      ),
    );
  }
}
