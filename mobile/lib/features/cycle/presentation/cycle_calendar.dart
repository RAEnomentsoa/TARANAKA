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
        if (marks[d] != DayMark.period && marks[d] != DayMark.ongoing) marks[d] = DayMark.predicted;
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
/// never colour alone, and a tooltip with its name. Tapping a logged period
/// edits it. Tapping another past day chooses the first day of a period, then
/// a second tap its last day (or "durée habituelle"). Tapping a future day
/// says what is expected that day, just under the grid.
class CycleCalendar extends StatefulWidget {
  const CycleCalendar({
    super.key,
    required this.periods,
    required this.summary,
    required this.today,
    required this.first,
    required this.onPeriodTap,
    required this.onRangePicked,
  });

  final List<Period> periods;
  final CycleSummary summary;
  final DateTime today;

  /// Earliest day that can be logged: the calendar does not go before its month.
  final DateTime first;
  final ValueChanged<Period> onPeriodTap;

  /// A new period chosen on the grid: its first day and, when chosen, its
  /// last day (null: the usual length, or still going on).
  final void Function(DateTime start, DateTime? end) onRangePicked;

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

  /// Legend under the calendar, left to right: period days, expected
  /// period, fertile window, ovulation, pregnancy possible.
  static const legend = [
    DayMark.period,
    DayMark.predicted,
    DayMark.fertile,
    DayMark.ovulation,
    DayMark.risk,
  ];

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

  /// Direction of the last month change (1 next, -1 previous): the new month
  /// slides in from that side.
  int _direction = 1;

  /// First day of a period being chosen on the grid (waiting for its last).
  DateTime? _rangeStart;

  /// Future day tapped: what is expected that day is shown under the grid.
  DateTime? _info;

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
    setState(() {
      _direction = months.sign;
      _month = target;
      _info = null;
    });
  }

  void _goTo(DateTime month) => setState(() {
    _direction = month.isBefore(_month) ? -1 : 1;
    _month = month;
    _info = null;
  });

  void _tap(DateTime date, Period? period) {
    final today = dateOnly(widget.today);
    if (period != null) {
      setState(() => _rangeStart = _info = null);
      widget.onPeriodTap(period);
      return;
    }
    if (date.isAfter(today)) {
      setState(() => _info = _info == date ? null : date);
      return;
    }
    final start = _rangeStart;
    if (start == null || date.isBefore(start)) {
      setState(() {
        _rangeStart = date;
        _info = null;
      });
      return;
    }
    setState(() => _rangeStart = null);
    widget.onRangePicked(start, date);
  }

  /// "Durée habituelle": the period lasts its usual length from the chosen
  /// day (the sheet leaves the end empty when it would be after today).
  void _useUsual() {
    final start = _rangeStart!;
    setState(() => _rangeStart = null);
    widget.onRangePicked(start, null);
  }

  /// Under the grid: the period being chosen (first day picked), or what is
  /// expected on the future day tapped. Nothing otherwise.
  Widget _panel(BuildContext context, Map<DateTime, DayMark> marks) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final start = _rangeStart;
    if (start != null) {
      return Container(
        key: const ValueKey('cal-range-panel'),
        width: double.infinity,
        margin: const EdgeInsets.only(top: Space.s),
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(Radii.m),
          border: Border.all(color: AppColors.accentSoftBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(l10n.rangeStartChosen(formatDate(start)), style: text.bodyMedium),
            ),
            const Gap(Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.xs,
              children: [
                FilledButton.tonal(
                  key: const ValueKey('cal-range-usual'),
                  onPressed: _useUsual,
                  child: Text(l10n.rangeUseUsual(widget.summary.periodDays)),
                ),
                TextButton(
                  key: const ValueKey('cal-range-cancel'),
                  onPressed: () => setState(() => _rangeStart = null),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final info = _info;
    if (info == null) return const SizedBox(width: double.infinity);
    final mark = marks[info];
    return Padding(
      key: ValueKey('cal-info-${isoDate(info)}'),
      padding: const EdgeInsets.only(top: Space.s),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            if (mark != null) ...[CycleSwatch(mark: mark), const SizedBox(width: Space.s)],
            Expanded(
              child: Text(
                mark == null
                    ? l10n.calendarDayInfoNone(formatDate(info))
                    : l10n.calendarDayInfo(
                        formatDate(info),
                        '${CycleCalendar.label(l10n, mark)} · '
                        '${CycleCalendar.logged(mark) ? l10n.calendarLogged : l10n.calendarEstimated}',
                      ),
                key: const ValueKey('cal-info'),
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
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
      return _Day(
        date: date,
        mark: marks[date],
        selected: date == _rangeStart || date == _info,
        // "Règles prévues": the pictogram on the exact date computed for the
        // next periods; the other expected days only have the dashed outline.
        showIcon: marks[date] != DayMark.predicted || starts.contains(date),
        isToday: date == today,
        height: cellHeight,
        onTap: () => _tap(date, period),
        future: date.isAfter(today),
      );
    }

    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final grid = Column(
      key: ValueKey('cal-grid-${_month.year}-${_month.month}'),
      children: [
        for (var r = 0; r < rows; r++)
          Row(children: [for (var c = 0; c < 7; c++) Expanded(child: cell(r * 7 + c))]),
      ],
    );

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
                    onPressed: () => _goTo(_monthOf(today)),
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
              ClipRect(
                child: AnimatedSwitcher(
                  duration: motion,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                  transitionBuilder: (child, animation) {
                    final incoming = child.key == grid.key;
                    final dx = (incoming ? 0.25 : -0.25) * _direction;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: Offset(dx, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    );
                  },
                  child: grid,
                ),
              ),
              AnimatedSize(
                duration: motion,
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _panel(context, marks),
              ),
              const Gap(Space.m),
              Text(
                l10n.calendarHint,
                key: const ValueKey('calendar-hint'),
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const Gap(Space.m),
              const _Legend(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logged days are solid red (white drop and number); estimated days are never
/// solid: a dashed outline or a pale fill, with an outlined pictogram.
/// Risk days are yellow, fertile days blue (a thin border keeps them visible
/// on any screen), ovulation blue with a strong border.
({Color? fill, Color? border, bool dashed, Color icon, Color text, double width}) _style(DayMark? m) =>
    switch (m) {
      DayMark.period || DayMark.ongoing => (
        fill: AppColors.danger,
        border: null,
        dashed: false,
        icon: AppColors.surface,
        text: AppColors.surface,
        width: 2,
      ),
      DayMark.predicted => (
        fill: AppColors.surface,
        border: AppColors.danger,
        dashed: true,
        icon: AppColors.danger,
        text: AppColors.danger,
        width: 2,
      ),
      DayMark.risk => (
        fill: AppColors.warningSoft,
        border: AppColors.cautionBorder,
        dashed: false,
        icon: AppColors.caution,
        text: AppColors.text,
        width: 1,
      ),
      DayMark.fertile => (
        fill: AppColors.accentSoft,
        border: AppColors.accentSoftBorder,
        dashed: false,
        icon: AppColors.accent,
        text: AppColors.text,
        width: 1,
      ),
      DayMark.ovulation => (
        fill: AppColors.accentSoft,
        border: AppColors.accent,
        dashed: false,
        icon: AppColors.accent,
        text: AppColors.text,
        width: 2,
      ),
      null => (fill: null, border: null, dashed: false, icon: AppColors.text, text: AppColors.text, width: 0),
    };

/// Legend colors: the logged period very red, the expected one pale.
const _legendPeriodRed = Color(0xFFC62828);
const _legendPredictedRed = Color(0xFFEF9A9A);

/// The legend, left to right: each mark with its pictogram on top and its
/// name under it. Equal columns, as many per line as the longest word allows
/// (narrow screen, large text, long Malagasy names): no word is ever cut.
class _Legend extends StatelessWidget {
  const _Legend();

  static Color _color(DayMark m) => switch (m) {
    DayMark.period || DayMark.ongoing => _legendPeriodRed,
    DayMark.predicted => _legendPredictedRed,
    _ => AppColors.accent,
  };

  static IconData _icon(DayMark m) => m == DayMark.predicted ? Icons.water_drop : CycleCalendar.icon(m);

  /// "Grossesse possible": the very look of its days on the calendar.
  static Widget _pictogram(DayMark m) => m == DayMark.risk
      ? const CycleSwatch(mark: DayMark.risk, size: _iconSize)
      : Icon(_icon(m), size: _iconSize, color: _color(m));

  static const double _iconSize = 24;
  static const double _gutter = Space.xs;

  double _longestWord(BuildContext context, Iterable<String> labels, TextStyle? style) {
    var longest = 0.0;
    for (final word in labels.expand((l) => l.split(' '))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      longest = math.max(longest, painter.width);
      painter.dispose();
    }
    return longest;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.bodySmall;
    const marks = CycleCalendar.legend;
    final labels = [for (final m in marks) CycleCalendar.label(l10n, m)];
    return LayoutBuilder(
      key: const ValueKey('cycle-legend'),
      builder: (context, constraints) {
        final column = _longestWord(context, labels, style).ceilToDouble() + _gutter;
        final perLine = (constraints.maxWidth / column).floor().clamp(1, marks.length);
        return Wrap(
          runSpacing: Space.s,
          children: [
            for (final (i, m) in marks.indexed)
              SizedBox(
                width: (constraints.maxWidth / perLine).floorToDouble(),
                child: Semantics(
                  container: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _gutter / 2),
                    child: Column(
                      children: [
                        ExcludeSemantics(child: _pictogram(m)),
                        const Gap(Space.xs),
                        Text(
                          labels[i],
                          key: ValueKey('legend-${m.name}'),
                          textAlign: TextAlign.center,
                          style: style,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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

/// The look of a calendar day, small: in the legend ("Grossesse possible") and
/// beside what is expected on the future day tapped.
class CycleSwatch extends StatelessWidget {
  const CycleSwatch({super.key, required this.mark, this.size = 22});
  final DayMark mark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = _style(mark);
    return CustomPaint(
      foregroundPainter: s.dashed ? _DashedBorder(color: s.border!, radius: Radii.s) : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: s.fill,
          borderRadius: BorderRadius.circular(Radii.s),
          border: s.border == null || s.dashed ? null : Border.all(color: s.border!, width: s.width),
        ),
        child: Icon(CycleCalendar.icon(mark), size: size * 0.64, color: s.icon),
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
    this.selected = false,
    this.future = false,
  });

  final DateTime date;
  final DayMark? mark;

  /// First day of a period being chosen, or the future day being described.
  final bool selected;

  /// After today: only predictions, never logged from the grid.
  final bool future;
  final bool showIcon;
  final bool isToday;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = _style(mark);
    // Today: a dark ring, over any mark (an estimated day keeps its dashes).
    final border = selected
        ? Border.all(color: AppColors.accent, width: 3)
        : isToday
        ? Border.all(color: AppColors.text, width: 2)
        : (s.border == null || s.dashed ? null : Border.all(color: s.border!, width: s.width));
    final markLabel = mark == null ? null : CycleCalendar.label(l10n, mark!);
    final semantics = [
      formatDate(date),
      if (isToday) l10n.today,
      ?markLabel,
      if (mark != null) CycleCalendar.logged(mark!) ? l10n.calendarLogged : l10n.calendarEstimated,
    ].join(', ');
    final day = Semantics(
      label: semantics,
      button: onTap != null,
      selected: selected,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: CustomPaint(
          foregroundPainter: s.dashed && !isToday && !selected
              ? _DashedBorder(color: s.border!, radius: Radii.s)
              : null,
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
                            color: future && mark == null ? AppColors.textMuted : s.text,
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
    // Long press on a marked day: its name, without looking for the legend.
    return markLabel == null
        ? day
        : Tooltip(
            message: markLabel,
            excludeFromSemantics: true,
            triggerMode: TooltipTriggerMode.longPress,
            child: day,
          );
  }
}
