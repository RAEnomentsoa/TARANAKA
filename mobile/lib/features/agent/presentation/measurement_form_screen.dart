import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';
import '../domain/screening.dart';
import 'agent_labels.dart';
import 'agent_scope.dart';
import 'screening_result_screen.dart';

/// Screening measurements (spec §7): weight, length/height, MUAC from 6
/// months, oedema, danger signs, appetite, complications.
class MeasurementFormScreen extends StatefulWidget {
  const MeasurementFormScreen({super.key, required this.childId});
  final String childId;

  @override
  State<MeasurementFormScreen> createState() => _MeasurementFormScreenState();
}

class _MeasurementFormScreenState extends State<MeasurementFormScreen> {
  final _weight = TextEditingController();
  final _length = TextEditingController();
  final _muac = TextEditingController();
  Child? _child;
  late DateTime _date;
  String? _position;
  String _oedema = 'aucun';
  final Set<String> _signs = {};
  String _appetite = 'non_teste';
  bool _complications = false;
  bool _feedingDifficulties = false;
  final Map<String, String> _fieldErrors = {};
  List<String> _problems = const [];
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_child != null) return;
    _date = dateOnly(AppScope.read(context).services.clock.now());
    AgentScope.read(context).repo.child(widget.childId).then((c) {
      if (mounted) setState(() => _child = c);
    });
  }

  @override
  void dispose() {
    _weight.dispose();
    _length.dispose();
    _muac.dispose();
    super.dispose();
  }

  int get _ageDays => ScreeningCalculator.ageDays(_child!.birthDate, _date);
  int get _ageMonths => _ageDays < 0 ? 0 : ScreeningCalculator.ageMonths(_ageDays);
  String get _positionValue => _position ?? ScreeningCalculator.defaultPosition(_ageDays);

  Future<void> _submit() async {
    final l10n = context.l10n;
    _fieldErrors.clear();
    final weight = parseDecimal(_weight.text);
    final length = parseDecimal(_length.text);
    final muacAllowed = _ageMonths >= ScreeningCalculator.muacMinMonths;
    final muac = muacAllowed && _muac.text.trim().isNotEmpty ? int.tryParse(_muac.text.trim()) : null;
    if (weight == null) _fieldErrors['weight'] = l10n.numberInvalid;
    if (length == null) _fieldErrors['length'] = l10n.numberInvalid;
    if (muacAllowed && _muac.text.trim().isNotEmpty && muac == null) {
      _fieldErrors['muac'] = l10n.numberInvalid;
    }
    if (_fieldErrors.isNotEmpty) {
      setState(() {});
      return;
    }
    final scope = AppScope.read(context);
    final agent = AgentScope.read(context);
    final input = ScreeningInput(
      sex: _child!.sex,
      birthDate: _child!.birthDate,
      measureDate: _date,
      weightKg: weight!,
      lengthCm: length!,
      position: _positionValue,
      muacMm: muac,
      oedema: _oedema,
      dangerSigns: _signs.toList(),
      complications: _complications,
      appetite: _appetite,
      breastfeedingDifficulties: _ageMonths < 6 && _feedingDifficulties,
    );
    final result = ScreeningCalculator.compute(
      input,
      scope.services.config.current,
      agent.tables,
      today: scope.services.clock.now(),
    );
    if (result.problems.isNotEmpty) {
      setState(
        () => _problems = [
          for (final p in result.problems)
            switch (p) {
              ScreeningProblem.measureBeforeBirth => l10n.problemBeforeBirth,
              ScreeningProblem.measureInFuture => l10n.problemFuture,
              ScreeningProblem.muacOutsideAge => l10n.problemMuacAge,
              ScreeningProblem.outsideAgeRange => l10n.problemAgeRange,
            },
        ],
      );
      return;
    }
    if (result.needsCheck) {
      final names = {'poids_kg': l10n.weightKg, 'taille_cm': l10n.lengthCm, 'pb_mm': l10n.muacMm};
      final fields = [
        ...result.outOfBounds.map((f) => names[f] ?? f),
        if (result.zOutOfRange) l10n.zscoresTitle,
      ].join(', ');
      final keep = await confirmAction(
        context,
        message: '${l10n.checkMeasureTitle}\n\n${l10n.checkMeasureText(fields)}',
        confirmLabel: l10n.checkMeasureKeep,
      );
      if (!keep || !mounted) return;
    }
    setState(() => _busy = true);
    final measurement = await agent.repo.saveMeasurement(
      child: _child!,
      input: input,
      result: result,
      agentId: agent.account!.user.id,
    );
    await agent.refreshCounts();
    if (!mounted) return;
    await pushAgent<void>(
      context,
      ScreeningResultScreen(child: _child!, input: input, result: result, measurement: measurement),
      replace: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final child = _child;
    if (child == null) return const Scaffold(body: LoadingView());
    final config = AppScope.of(context).services.config.current;
    final today = AppScope.of(context).services.clock.now();
    final muacAllowed = _ageDays >= 0 && _ageMonths >= ScreeningCalculator.muacMinMonths;
    return AppScreen(
      title: child.name,
      bottomAction: FilledButton.icon(
        key: const ValueKey('measure-submit'),
        onPressed: _busy ? null : _submit,
        icon: const Icon(Icons.check),
        label: Text(l10n.computeResult),
      ),
      children: [
        StatusPill(
          icon: child.sex == 'F' ? Icons.girl : Icons.boy,
          label: '${child.sex == 'F' ? l10n.sexF : l10n.sexM} · ${l10n.ageMonths(_ageMonths)}',
          tone: Tone.info,
        ),
        const Gap(Space.m),
        for (final p in _problems) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: p),
          const Gap(Space.s),
        ],
        DateField(
          label: l10n.measureDate,
          value: _date,
          first: child.birthDate,
          last: today,
          onChanged: (d) => setState(() => _date = d),
        ),
        const Gap(Space.m),
        _number(_weight, l10n.weightKg, 'weight', Icons.monitor_weight_outlined),
        const Gap(Space.m),
        _number(_length, l10n.lengthCm, 'length', Icons.height),
        const Gap(Space.s),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'couche',
              icon: const Icon(Icons.airline_seat_flat),
              label: Text(l10n.positionLying),
            ),
            ButtonSegment(
              value: 'debout',
              icon: const Icon(Icons.accessibility_new),
              label: Text(l10n.positionStanding),
            ),
          ],
          selected: {_positionValue},
          onSelectionChanged: (s) => setState(() => _position = s.first),
        ),
        const Gap(Space.m),
        if (muacAllowed)
          _number(_muac, l10n.muacMm, 'muac', Icons.straighten, decimal: false)
        else
          NoticeBox(icon: Icons.info_outline, text: l10n.muacOnlyFrom6),
        SectionTitle(l10n.oedema),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final o in const ['aucun', '+', '++', '+++'])
              ChoiceChip(
                key: ValueKey('oedema-$o'),
                label: Text(o == 'aucun' ? l10n.oedemaNone : o),
                selected: _oedema == o,
                onSelected: (_) => setState(() => _oedema = o),
              ),
          ],
        ),
        SectionTitle(l10n.dangerSigns),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (code, label) in childDangerSigns(config, context.lang))
              FilterChip(
                key: ValueKey('sign-$code'),
                avatar: const Icon(Icons.warning_amber, size: 18),
                label: Text(label),
                selected: _signs.contains(code),
                onSelected: (v) => setState(() => v ? _signs.add(code) : _signs.remove(code)),
              ),
          ],
        ),
        SectionTitle(l10n.appetite),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (v, label) in [
              ('non_teste', l10n.appetiteNotTested),
              ('bon', l10n.appetiteGood),
              ('mauvais', l10n.appetitePoor),
            ])
              ChoiceChip(
                key: ValueKey('appetite-$v'),
                label: Text(label),
                selected: _appetite == v,
                onSelected: (_) => setState(() => _appetite = v),
              ),
          ],
        ),
        const Gap(Space.m),
        SwitchListTile(
          key: const ValueKey('complications'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.complications),
          value: _complications,
          onChanged: (v) => setState(() => _complications = v),
        ),
        if (_ageMonths < 6)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.feedingDifficulties),
            value: _feedingDifficulties,
            onChanged: (v) => setState(() => _feedingDifficulties = v),
          ),
        const Gap(Space.xl),
      ],
    );
  }

  Widget _number(TextEditingController c, String label, String key, IconData icon, {bool decimal = true}) =>
      TextField(
        key: ValueKey('field-$key'),
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), errorText: _fieldErrors[key]),
      );
}
