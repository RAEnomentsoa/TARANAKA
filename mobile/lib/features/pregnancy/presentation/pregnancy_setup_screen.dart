import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/pregnancy.dart';

/// DDR or a term confirmed by a professional (spec §5).
class PregnancySetupForm extends StatefulWidget {
  const PregnancySetupForm({super.key, this.initial, required this.onSave, this.title});

  final PregnancyDates? initial;
  final Future<void> Function(PregnancyDates) onSave;
  final String? title;

  @override
  State<PregnancySetupForm> createState() => _PregnancySetupFormState();
}

class _PregnancySetupFormState extends State<PregnancySetupForm> {
  late bool _confirmed = widget.initial?.hasConfirmedTerm ?? false;
  late DateTime? _lmp = widget.initial?.lmp;
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
    if (_confirmed) {
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
        const Gap(Space.m),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, icon: const Icon(Icons.water_drop_outlined), label: Text(l10n.byLmp)),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.medical_information_outlined),
              label: Text(l10n.byConfirmed),
            ),
          ],
          selected: {_confirmed},
          onSelectionChanged: (s) => setState(() {
            _confirmed = s.first;
            _error = null;
          }),
        ),
        const Gap(Space.l),
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.m),
        ],
        if (!_confirmed)
          DateField(
            key: const ValueKey('lmp-field'),
            label: l10n.byLmp,
            value: _lmp,
            first: addDays(today, -300),
            last: today,
            onChanged: (d) => setState(() => _lmp = d),
          )
        else ...[
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
