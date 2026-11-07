import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/pregnancy.dart';

enum _DatingMode { lmp, confirmed, due }

/// DDR, a term confirmed by a professional (spec §5), or the expected due date
/// (DPA) itself – future, or past for a follow-up entered afterwards.
class PregnancySetupForm extends StatefulWidget {
  const PregnancySetupForm({super.key, this.initial, required this.onSave, this.title});

  final PregnancyDates? initial;
  final Future<void> Function(PregnancyDates) onSave;
  final String? title;

  @override
  State<PregnancySetupForm> createState() => _PregnancySetupFormState();
}

class _PregnancySetupFormState extends State<PregnancySetupForm> {
  late _DatingMode _mode = switch (widget.initial) {
    final i? when i.hasConfirmedTerm => _DatingMode.confirmed,
    final i? when i.lmp == null && i.dueOn != null => _DatingMode.due,
    _ => _DatingMode.lmp,
  };
  late DateTime? _lmp = widget.initial?.lmp;
  late DateTime? _due = widget.initial?.dueOn;
  late DateTime? _exam = widget.initial?.confirmedOn;
  late final _weeks = TextEditingController(
    text: widget.initial?.confirmedAgeDays == null ? '' : '${widget.initial!.confirmedAgeDays! ~/ 7}',
  );
  late final _days = TextEditingController(
    text: widget.initial?.confirmedAgeDays == null ? '' : '${widget.initial!.confirmedAgeDays! % 7}',
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _weeks.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final scope = AppScope.read(context);
    final today = dateOnly(scope.services.clock.now());
    final calc = PregnancyCalculator(scope.services.config.current);
    PregnancyDates dates;
    if (_mode == _DatingMode.due) {
      if (_due == null) {
        setState(() => _error = l10n.fieldRequired);
        return;
      }
      // A past DPA is allowed (follow-up entered afterwards, correction).
      setState(() => _busy = true);
      await widget.onSave(PregnancyDates(dueOn: _due));
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (_mode == _DatingMode.confirmed) {
      final w = int.tryParse(_weeks.text.trim());
      final d = int.tryParse(_days.text.trim().isEmpty ? '0' : _days.text.trim());
      if (_exam == null || w == null || d == null || d < 0 || d > 6) {
        setState(() => _error = l10n.fieldRequired);
        return;
      }
      dates = PregnancyDates(lmp: _lmp, confirmedOn: _exam, confirmedAgeDays: w * 7 + d);
    } else {
      if (_lmp == null) {
        setState(() => _error = l10n.fieldRequired);
        return;
      }
      dates = PregnancyDates(
        lmp: _lmp,
        confirmedOn: widget.initial?.confirmedOn,
        confirmedAgeDays: widget.initial?.confirmedAgeDays,
      );
    }
    final ga = calc.age(dates, today)!;
    if (ga.totalDays < 0 || ga.weeks > 42) {
      setState(() => _error = l10n.gaInvalid);
      return;
    }
    setState(() => _busy = true);
    await widget.onSave(dates);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = dateOnly(AppScope.of(context).services.clock.now());
    return AppScreen(
      title: widget.title ?? l10n.pregnancySetupTitle,
      bottomAction: FilledButton(
        key: const ValueKey('pregnancy-save'),
        onPressed: _busy ? null : _save,
        child: Text(widget.initial == null ? l10n.startPregnancy : l10n.save),
      ),
      children: [
        Text(l10n.pregnancySetupHow, style: Theme.of(context).textTheme.titleMedium),
        const Gap(Space.s),
        // A vertical list: the three long labels stay readable at 320 dp.
        RadioGroup<_DatingMode>(
          groupValue: _mode,
          onChanged: (v) => setState(() {
            _mode = v ?? _mode;
            _error = null;
          }),
          child: Column(
            children: [
              for (final (mode, icon, label) in [
                (_DatingMode.lmp, Icons.water_drop_outlined, l10n.byLmp),
                (_DatingMode.confirmed, Icons.medical_information_outlined, l10n.byConfirmed),
                (_DatingMode.due, Icons.event_outlined, l10n.byDueDate),
              ])
                RadioListTile<_DatingMode>(
                  key: ValueKey('dating-${mode.name}'),
                  value: mode,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(icon, color: AppColors.accent),
                  title: Text(label),
                ),
            ],
          ),
        ),
        const Gap(Space.m),
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.m),
        ],
        if (_mode == _DatingMode.lmp)
          DateField(
            key: const ValueKey('lmp-field'),
            label: l10n.byLmp,
            value: _lmp,
            first: addDays(today, -300),
            last: today,
            initial: addDays(today, -60),
            onChanged: (d) => setState(() => _lmp = d),
          )
        else if (_mode == _DatingMode.due) ...[
          DateField(
            key: const ValueKey('due-field'),
            label: l10n.byDueDate,
            value: _due,
            // Up to one year in the past, up to a full term ahead.
            first: addDays(today, -365),
            last: addDays(
              today,
              PregnancyCalculator(AppScope.of(context).services.config.current).naegeleDays,
            ),
            initial: addDays(today, 140),
            onChanged: (d) => setState(() => _due = d),
          ),
          const Gap(Space.s),
          Text(l10n.dueDateHint, style: Theme.of(context).textTheme.bodySmall),
        ] else ...[
          DateField(
            label: l10n.confirmedExamDate,
            value: _exam,
            first: addDays(today, -300),
            last: today,
            onChanged: (d) => setState(() => _exam = d),
          ),
          const Gap(Space.m),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const ValueKey('confirmed-weeks'),
                  controller: _weeks,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.confirmedWeeks),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('confirmed-days'),
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.confirmedDays),
                ),
              ),
            ],
          ),
          const Gap(Space.m),
          NoticeBox(icon: Icons.info_outline, text: l10n.confirmedWins),
        ],
        const Gap(Space.l),
        Text(l10n.pregnancyLocal, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
