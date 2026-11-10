import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../i18n/l10n.dart';
import '../theme/tokens.dart';

/// Opens a time picker in a bottom sheet: the hour wheel on the left, the
/// minute wheel on the right ("HH : MM", 24 h), read from left to right like
/// a clock. Returns null when dismissed.
Future<TimeOfDay?> showTimeWheel(BuildContext context, {required String title, required TimeOfDay initial}) =>
    showModalBottomSheet<TimeOfDay>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => TimeWheelSheet(title: title, initial: initial),
    );

class TimeWheelSheet extends StatefulWidget {
  const TimeWheelSheet({super.key, required this.title, required this.initial});

  final String title;
  final TimeOfDay initial;

  @override
  State<TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<TimeWheelSheet> {
  late TimeOfDay _value = widget.initial;
  late final _hour = FixedExtentScrollController(initialItem: widget.initial.hour);
  late final _minute = FixedExtentScrollController(initialItem: widget.initial.minute);

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final extent = math.max(Space.touch, 40 * MediaQuery.textScalerOf(context).scale(1));
    final now = context.getInheritedWidgetOfExactType<AppScope>()?.services.clock.now() ?? DateTime.now();

    Widget wheel(String label, FixedExtentScrollController c, int count, ValueChanged<int> onChanged) =>
        Expanded(
          child: Semantics(
            label: label,
            child: CupertinoPicker.builder(
              scrollController: c,
              itemExtent: extent,
              childCount: count,
              onSelectedItemChanged: onChanged,
              selectionOverlay: const DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.symmetric(horizontal: BorderSide(color: AppColors.accent, width: 1.5)),
                ),
              ),
              itemBuilder: (context, i) => Center(
                child: Text(_two(i), style: text.headlineSmall?.copyWith(color: AppColors.text)),
              ),
            ),
          ),
        );

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
              '${_two(_value.hour)}:${_two(_value.minute)}',
              key: const ValueKey('time-wheel-value'),
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Space.m),
            // Labels over the wheels: hour (left), minute (right).
            Row(
              children: [
                Expanded(
                  child: Text(l10n.wheelHour, textAlign: TextAlign.center, style: text.labelLarge),
                ),
                const SizedBox(width: Space.xl),
                Expanded(
                  child: Text(l10n.wheelMinute, textAlign: TextAlign.center, style: text.labelLarge),
                ),
              ],
            ),
            SizedBox(
              height: extent * 5,
              child: Row(
                children: [
                  wheel(
                    l10n.wheelHour,
                    _hour,
                    24,
                    (h) => setState(() => _value = TimeOfDay(hour: h, minute: _value.minute)),
                  ),
                  SizedBox(
                    width: Space.xl,
                    child: Text(':', textAlign: TextAlign.center, style: text.headlineSmall),
                  ),
                  wheel(
                    l10n.wheelMinute,
                    _minute,
                    60,
                    (m) => setState(() => _value = TimeOfDay(hour: _value.hour, minute: m)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.l),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('time-wheel-now'),
                    onPressed: () => Navigator.of(context).pop(TimeOfDay.fromDateTime(now)),
                    child: Text(l10n.now),
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('time-wheel-ok'),
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
