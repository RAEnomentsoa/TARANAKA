import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../i18n/l10n.dart';
import '../theme/tokens.dart';
import '../util/clock.dart';

/// A date (and optionally a time) shown as dd/MM/yyyy, picked with scroll
/// wheels (day · month · year [· hour · minute]) instead of a calendar grid:
/// one gesture per part, no typing, works at 320 dp and with large text.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.first,
    required this.last,
    this.errorText,
    this.withTime = false,
    this.onCleared,
    this.initial,
    this.emptyText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime first;
  final DateTime last;
  final String? errorText;

  /// Adds hour and minute wheels.
  final bool withTime;

  /// When given, a "remove" button lets the user empty the field.
  final VoidCallback? onCleared;

  /// Wheel position when [value] is null (defaults to [last]).
  final DateTime? initial;

  /// Shown when [value] is null (defaults to "Choose the date").
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final v = value;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.m),
      onTap: () async {
        final picked = await showDateWheel(
          context,
          title: label,
          initial: v ?? initial ?? last,
          first: first,
          last: last,
          withTime: withTime,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: Icon(withTime ? Icons.schedule : Icons.event_outlined),
          suffixIcon: v != null && onCleared != null
              ? IconButton(tooltip: l10n.clearDate, icon: const Icon(Icons.close), onPressed: onCleared)
              : const Icon(Icons.unfold_more),
        ),
        child: Text(
          v == null ? (emptyText ?? l10n.chooseDate) : (withTime ? formatDateTime(v) : formatDate(v)),
        ),
      ),
    );
  }
}

/// Opens the wheel picker in a bottom sheet. Returns null when dismissed.
Future<DateTime?> showDateWheel(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime first,
  required DateTime last,
  bool withTime = false,
}) => showModalBottomSheet<DateTime>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) =>
      DateWheelSheet(title: title, initial: initial, first: first, last: last, withTime: withTime),
);

class DateWheelSheet extends StatefulWidget {
  const DateWheelSheet({
    super.key,
    required this.title,
    required this.initial,
    required this.first,
    required this.last,
    this.withTime = false,
  });

  final String title;
  final DateTime initial;
  final DateTime first;
  final DateTime last;
  final bool withTime;

  @override
  State<DateWheelSheet> createState() => _DateWheelSheetState();
}

class _DateWheelSheetState extends State<DateWheelSheet> {
  late DateTime _first;
  late DateTime _last;
  late DateTime _value;
  late final FixedExtentScrollController _day;
  late final FixedExtentScrollController _month;
  late final FixedExtentScrollController _year;
  late final FixedExtentScrollController _hour;
  late final FixedExtentScrollController _minute;

  @override
  void initState() {
    super.initState();
    // Without time, bounds are whole days.
    _first = widget.withTime ? widget.first : dateOnly(widget.first);
    _last = widget.withTime ? widget.last : dateOnly(widget.last);
    if (_last.isBefore(_first)) _last = _first;
    _value = _clamp(widget.withTime ? widget.initial : dateOnly(widget.initial));
    _day = FixedExtentScrollController(initialItem: _value.day - 1);
    _month = FixedExtentScrollController(initialItem: _value.month - 1);
    _year = FixedExtentScrollController(initialItem: _value.year - _first.year);
    _hour = FixedExtentScrollController(initialItem: _value.hour);
    _minute = FixedExtentScrollController(initialItem: _value.minute);
  }

  @override
  void dispose() {
    for (final c in [_day, _month, _year, _hour, _minute]) {
      c.dispose();
    }
    super.dispose();
  }

  static int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  DateTime _clamp(DateTime d) => d.isBefore(_first) ? _first : (d.isAfter(_last) ? _last : d);

  void _set({int? year, int? month, int? day, int? hour, int? minute}) {
    final y = year ?? _value.year;
    final m = month ?? _value.month;
    final d = math.min(day ?? _value.day, _daysIn(y, m));
    final next = _clamp(DateTime(y, m, d, hour ?? _value.hour, minute ?? _value.minute));
    if (next == _value) return;
    setState(() => _value = next);
    // Wheels that disagree with the (clamped) value jump to it, without
    // animation, so their own change callbacks stay quiet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync(_day, next.day - 1);
      _sync(_month, next.month - 1);
      _sync(_year, next.year - _first.year);
      if (widget.withTime) {
        _sync(_hour, next.hour);
        _sync(_minute, next.minute);
      }
    });
  }

  void _sync(FixedExtentScrollController c, int item) {
    if (c.hasClients && c.selectedItem != item) c.jumpToItem(item);
  }

  bool _dayOut(int d) {
    final start = DateTime(_value.year, _value.month, d);
    return DateTime(_value.year, _value.month, d, 23, 59).isBefore(_first) || start.isAfter(_last);
  }

  bool _monthOut(int m) =>
      DateTime(_value.year, m + 1, 0, 23, 59).isBefore(_first) || DateTime(_value.year, m).isAfter(_last);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final months = l10n.monthNames.split('|');
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final extent = math.max(Space.touch, 36 * scale);
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    final now = scope?.services.clock.now() ?? DateTime.now();
    final today = widget.withTime ? now : dateOnly(now);
    final canToday = !today.isBefore(_first) && !today.isAfter(_last);
    final yearCount = _last.year - _first.year + 1;

    Widget wheel({
      required String label,
      required FixedExtentScrollController controller,
      required int count,
      required String Function(int) itemText,
      required ValueChanged<int> onChanged,
      bool Function(int)? disabled,
      int flex = 2,
    }) => Expanded(
      flex: flex,
      child: Semantics(
        label: label,
        child: CupertinoPicker.builder(
          scrollController: controller,
          itemExtent: extent,
          childCount: count,
          onSelectedItemChanged: onChanged,
          // Lines only: a filled band would wash out the chosen value.
          selectionOverlay: const DecoratedBox(
            decoration: BoxDecoration(
              border: Border.symmetric(horizontal: BorderSide(color: AppColors.accent, width: 1.5)),
            ),
          ),
          itemBuilder: (context, i) => Center(
            child: Text(
              itemText(i),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                color: disabled?.call(i) == true ? AppColors.outline : AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );

    String two(int n) => n.toString().padLeft(2, '0');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: Space.xs),
            Text(
              widget.withTime ? formatDateTime(_value) : formatDate(_value),
              key: const ValueKey('date-wheel-value'),
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.m),
            SizedBox(
              height: extent * 5,
              child: Row(
                children: [
                  wheel(
                    label: l10n.wheelDay,
                    controller: _day,
                    count: _daysIn(_value.year, _value.month),
                    itemText: (i) => two(i + 1),
                    disabled: (i) => _dayOut(i + 1),
                    onChanged: (i) => _set(day: i + 1),
                  ),
                  wheel(
                    label: l10n.wheelMonth,
                    controller: _month,
                    count: 12,
                    flex: 4,
                    itemText: (i) => months.length == 12 ? months[i] : two(i + 1),
                    disabled: _monthOut,
                    onChanged: (i) => _set(month: i + 1),
                  ),
                  wheel(
                    label: l10n.wheelYear,
                    controller: _year,
                    count: yearCount,
                    flex: 3,
                    itemText: (i) => '${_first.year + i}',
                    onChanged: (i) => _set(year: _first.year + i),
                  ),
                  if (widget.withTime) ...[
                    const SizedBox(width: Space.s),
                    wheel(
                      label: l10n.wheelHour,
                      controller: _hour,
                      count: 24,
                      itemText: two,
                      onChanged: (i) => _set(hour: i),
                    ),
                    wheel(
                      label: l10n.wheelMinute,
                      controller: _minute,
                      count: 60,
                      itemText: two,
                      onChanged: (i) => _set(minute: i),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Space.l),
            Row(
              children: [
                if (canToday)
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('date-wheel-today'),
                      onPressed: () => Navigator.of(context).pop(today),
                      child: Text(widget.withTime ? l10n.now : l10n.today),
                    ),
                  ),
                if (canToday) const SizedBox(width: Space.m),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('date-wheel-ok'),
                    onPressed: () => Navigator.of(context).pop(_value),
                    child: Text(l10n.confirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
