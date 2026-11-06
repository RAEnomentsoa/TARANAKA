import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cores/l10n/labels.dart';
import '../../cores/providers/language_provider.dart';
import '../../cores/services/cycle_timeline.dart';
import '../../cores/services/days.dart';
import '../../cores/themes/app_colors.dart';
import 'phase_style.dart';

/// Calendrier mensuel. Il remplace celui de Material, qui n'existe pas en
/// malagasy. Laisser au moins 44 px par colonne : 7 cellules sur la largeur.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.language,
    required this.today,
    required this.onDaySelected,
    this.selected,
    this.firstDay,
    this.lastDay,
    this.markOf,
    this.expectedDay,
  });

  final AppLanguage language;
  final DateTime today;
  final ValueChanged<DateTime> onDaySelected;
  final DateTime? selected;

  /// Bornes des jours sélectionnables.
  final DateTime? firstDay;
  final DateTime? lastDay;
  final DayMark? Function(DateTime day)? markOf;

  /// Jour des prochaines règles attendues (`estimationProchain`), marqué d'un
  /// drapeau.
  final DateTime? expectedDay;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime _month = _monthOf(widget.selected ?? widget.today);

  static DateTime _monthOf(DateTime day) => DateTime.utc(day.year, day.month);

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime.utc(_month.year, _month.month + delta));

  bool _isEnabled(DateTime day) =>
      !(widget.firstDay?.isAfter(day) ?? false) &&
      !(widget.lastDay?.isBefore(day) ?? false);

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final firstOfMonth = _month;
    // Les semaines commencent le lundi.
    final gridStart = addDays(firstOfMonth, 1 - firstOfMonth.weekday);
    final monthEnd = DateTime.utc(_month.year, _month.month + 1, 0);
    final weeks = (daysBetween(gridStart, monthEnd) ~/ 7) + 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('calendar-previous'),
              onPressed: () => _shiftMonth(-1),
              tooltip: language.pick(
                mg: 'Volana teo aloha',
                fr: 'Mois précédent',
              ),
              icon: const Icon(Symbols.chevron_left),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            Expanded(
              child: Text(
                '${language.monthName(_month.month)} ${_month.year}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: const ValueKey('calendar-next'),
              onPressed: () => _shiftMonth(1),
              tooltip: language.pick(mg: 'Volana manaraka', fr: 'Mois suivant'),
              icon: const Icon(Symbols.chevron_right),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ],
        ),
        Row(
          children: [
            for (var weekday = 1; weekday <= 7; weekday++)
              Expanded(
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        language.weekdayShort(weekday),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var week = 0; week < weeks; week++)
          Row(
            children: [
              for (var offset = 0; offset < 7; offset++)
                Expanded(child: _cell(addDays(gridStart, week * 7 + offset))),
            ],
          ),
      ],
    );
  }

  Widget _cell(DateTime day) {
    if (day.month != _month.month) return const SizedBox(height: _cellHeight);
    return _DayCell(
      language: widget.language,
      day: day,
      mark: widget.markOf?.call(day),
      isToday: day == widget.today,
      isExpected: day == widget.expectedDay,
      isSelected: day == widget.selected,
      onTap: _isEnabled(day) ? () => widget.onDaySelected(day) : null,
    );
  }

  static const double _cellHeight = 48;
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.language,
    required this.day,
    required this.mark,
    required this.isToday,
    required this.isExpected,
    required this.isSelected,
    required this.onTap,
  });

  final AppLanguage language;
  final DateTime day;
  final DayMark? mark;
  final bool isToday;
  final bool isExpected;
  final bool isSelected;
  final VoidCallback? onTap;

  String get _semanticLabel {
    final mark = this.mark;
    return [
      language.formatDate(day),
      if (isToday) language.pick(mg: 'Androany', fr: 'Aujourd’hui'),
      if (mark != null) language.phaseName(mark.phase),
      if (mark != null && mark.forecast)
        language.pick(mg: 'Vinavina', fr: 'Prévision'),
      if (isExpected) language.expectedPeriodName,
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final mark = this.mark;
    final phase = mark?.phase;
    final isSolid = mark != null && !mark.forecast;

    final Color textColor;
    if (onTap == null) {
      textColor = AppColors.ink.withValues(alpha: 0.38);
    } else if (isSolid) {
      textColor = phase!.onColor;
    } else {
      textColor = AppColors.ink;
    }

    // Une prévision se distingue par son fond pâle et son contour coloré.
    final decoration = BoxDecoration(
      color: phase == null
          ? null
          : isSolid
          ? phase.color
          : phase.color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(8),
      border: isSelected || isToday
          ? Border.all(
              color: isSelected ? AppColors.primaryDark : AppColors.ink,
              width: isSelected ? 3 : 2,
            )
          : phase != null && !isSolid
          ? Border.all(color: phase.color, width: 1.5)
          : null,
    );

    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: isSelected,
      label: _semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: _MonthCalendarState._cellHeight,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Container(
              key: ValueKey('day-${formatDay(day)}'),
              decoration: decoration,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: isToday || isSelected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isExpected)
                    Positioned(
                      key: const ValueKey('expected-flag'),
                      top: 1,
                      right: 1,
                      child: const Icon(
                        Symbols.flag,
                        size: 14,
                        fill: 1,
                        color: AppColors.ink,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fait choisir un jour dans une feuille modale.
Future<DateTime?> showDayPicker(
  BuildContext context, {
  required AppLanguage language,
  required DateTime today,
  required DateTime initialDay,
  DateTime? firstDay,
  DateTime? lastDay,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
      child: MonthCalendar(
        language: language,
        today: today,
        selected: initialDay,
        firstDay: firstDay,
        lastDay: lastDay,
        onDaySelected: (day) => Navigator.pop(context, day),
      ),
    ),
  ),
);
