import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../pregnancy/presentation/pregnancy_home_screen.dart';
import '../data/cycle_repository.dart';
import '../domain/cycle.dart';
import 'cycle_calendar.dart';

CycleRepository cycleRepository(BuildContext context) {
  final scope = AppScope.read(context);
  return CycleRepository(scope.session.active!.db, clock: scope.services.clock);
}

/// "Mon cycle" (spec §4). The most frequent action, "mes règles ont commencé
/// aujourd'hui", is the main button (home → Mon cycle → button: 2 taps).
class CycleHomeScreen extends StatefulWidget {
  const CycleHomeScreen({super.key});

  @override
  State<CycleHomeScreen> createState() => _CycleHomeScreenState();
}

class _CycleHomeScreenState extends State<CycleHomeScreen> {
  /// The periods and the usual length chosen by the user (null: none).
  Future<(List<Period>, int?)>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  /// Periods whose end was forgotten are closed at their usual length first,
  /// so they never run over the whole month.
  Future<(List<Period>, int?)> _load() async {
    final scope = AppScope.read(context);
    final repo = cycleRepository(context);
    final calc = CycleCalculator(scope.services.config.current);
    final today = dateOnly(scope.services.clock.now());
    final setting = await repo.periodDays();
    final periods = await repo.periods();
    await repo.closeForgotten(today, calc.summarise(periods, today, periodDays: setting).periodDays);
    return (await repo.periods(), setting);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  Future<void> _setPeriodDays(int days) async {
    await cycleRepository(context).setPeriodDays(days);
    _reload();
  }

  Future<void> _startOn(DateTime day) async {
    await cycleRepository(context).start(day);
    _reload();
  }

  /// Adds a past period ([period] null) or edits one.
  Future<void> _openSheet(
    Period? period,
    List<Period> periods,
    DateTime today,
    int periodDays, {
    DateTime? start,
  }) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _PeriodSheet(period: period, periods: periods, today: today, periodDays: periodDays, start: start),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final calc = CycleCalculator(config);
    final today = dateOnly(scope.services.clock.now());
    final warning = localizedText(config.cycle['avertissement'], context.lang);

    return FutureBuilder<(List<Period>, int?)>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: ErrorView(onRetry: _reload));
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (periods, setting) = snap.data!;
        final s = calc.summarise(periods, today, periodDays: setting);
        final ongoing = calc.ongoing(periods, today, periodDays: s.periodDays);
        final text = Theme.of(context).textTheme;

        return AppScreen(
          title: l10n.tileCycle,
          bottomAction: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Permanent warning (spec §4).
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Text(warning, key: const ValueKey('cycle-warning'), style: text.bodySmall),
                    ),
                  ],
                ),
              ),
              if (ongoing == null)
                FilledButton.icon(
                  key: const ValueKey('period-start-today'),
                  onPressed: () => _startOn(today),
                  icon: const Icon(Icons.water_drop),
                  label: Text(l10n.periodStartedToday),
                )
              else
                FilledButton.icon(
                  key: const ValueKey('period-end-today'),
                  onPressed: () async {
                    await cycleRepository(context).end(ongoing.id, today);
                    _reload();
                  },
                  icon: const Icon(Icons.check),
                  label: Text(l10n.periodEndedToday),
                ),
            ],
          ),
          children: [
            Text(
              l10n.cycleIntro,
              key: const ValueKey('cycle-intro'),
              style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
            ),
            const Gap(Space.l),
            if (ongoing != null) ...[
              StatusPill(
                icon: Icons.water_drop,
                label: l10n.periodOngoing(formatDate(ongoing.start)),
                tone: Tone.danger,
              ),
              const Gap(Space.m),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('period-end-other-day'),
                  onPressed: () async {
                    final picked = await showDateWheel(
                      context,
                      title: l10n.periodEndDate,
                      initial: today,
                      first: ongoing.start,
                      last: today,
                    );
                    if (picked == null || !context.mounted) return;
                    await cycleRepository(context).end(ongoing.id, picked);
                    _reload();
                  },
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(l10n.periodEndOtherDay),
                ),
              ),
              const Gap(Space.s),
              _TodayDetails(period: ongoing, onChanged: _reload),
              const Gap(Space.l),
            ],
            _PredictionCard(summary: s, calc: calc, today: today),
            for (final signal in s.signals) ...[
              const Gap(Space.m),
              _SignalBox(signal: signal, summary: s, calc: calc),
            ],
            SectionTitle(l10n.calendarTitle),
            CycleCalendar(
              key: const ValueKey('cycle-calendar'),
              periods: periods,
              summary: s,
              today: today,
              first: _PeriodSheet.firstDay(today),
              onPeriodTap: (p) => _openSheet(p, periods, today, s.periodDays),
              onDayTap: (d) => _openSheet(null, periods, today, s.periodDays, start: d),
            ),
            SectionTitle(l10n.cycleStats),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                StatusPill(icon: Icons.repeat, label: l10n.cyclesCount(s.periodsLogged), tone: Tone.neutral),
                if (s.averageCycle != null)
                  StatusPill(
                    icon: Icons.loop,
                    label: l10n.averageCycle(formatDecimal(s.averageCycle!, digits: 0)),
                    tone: Tone.info,
                  ),
                if (s.averagePeriod != null)
                  StatusPill(
                    icon: Icons.water_drop_outlined,
                    label: l10n.averagePeriod(formatDecimal(s.averagePeriod!, digits: 0)),
                    tone: Tone.info,
                  ),
                if (s.regular != null)
                  StatusPill(
                    icon: s.regular! ? Icons.check_circle_outline : Icons.shuffle,
                    label: s.regular! ? l10n.cycleRegular : l10n.cycleIrregular,
                    tone: s.regular! ? Tone.success : Tone.warning,
                  ),
              ],
            ),
            const Gap(Space.m),
            _PeriodLength(days: s.periodDays.clamp(periodDaysMin, periodDaysMax), onChanged: _setPeriodDays),
            SectionTitle(l10n.periodHistory),
            OutlinedButton.icon(
              key: const ValueKey('period-add-past'),
              onPressed: () => _openSheet(null, periods, today, s.periodDays),
              icon: const Icon(Icons.history),
              label: Text(l10n.periodAddPast),
            ),
            const Gap(Space.s),
            for (final p in periods)
              Card(
                child: ListTile(
                  key: ValueKey('period-${isoDate(p.start)}'),
                  leading: const Icon(Icons.water_drop, color: AppColors.danger),
                  title: Text(
                    p.end == null
                        ? l10n.periodNoEnd(formatDate(p.start))
                        : l10n.periodDays(formatDate(p.start), formatDate(p.end!), p.length!),
                  ),
                  subtitle: _periodSubtitle(l10n, p),
                  trailing: Icon(Icons.edit_outlined, semanticLabel: l10n.editPeriod),
                  onTap: () => _openSheet(p, periods, today, s.periodDays),
                ),
              ),
            const Gap(Space.l),
            Text(config.sourceLabel('cycle'), style: text.bodySmall),
          ],
        );
      },
    );
  }
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.summary, required this.calc, required this.today});

  final CycleSummary summary;
  final CycleCalculator calc;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = summary;
    final text = Theme.of(context).textTheme;
    // No period logged yet: nothing to predict (the intro says what to do).
    if (s.nextPeriod == null) return const SizedBox.shrink();
    final reliable = s.confidence == Confidence.reliable;
    final inDays = daysBetween(today, s.nextPeriod!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabelWithPill(
              label: Text(l10n.nextPeriod, style: text.labelLarge?.copyWith(color: AppColors.textMuted)),
              pill: StatusPill(
                key: const ValueKey('cycle-confidence'),
                icon: reliable ? Icons.verified_outlined : Icons.help_outline,
                label: reliable ? l10n.confidenceReliable : l10n.confidenceEstimate,
                tone: reliable ? Tone.success : Tone.caution,
              ),
            ),
            Text(
              l10n.nextPeriodOn(formatDate(s.nextPeriod!)),
              key: const ValueKey('next-period'),
              style: text.headlineSmall,
            ),
            if (inDays >= 0) Text(l10n.nextPeriodIn(inDays)),
            const Gap(Space.m),
            Row(
              children: [
                const Icon(Icons.spa_outlined, color: AppColors.accent),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    '${l10n.fertileWindow} : ${l10n.fertileFromTo(formatDate(s.fertileStart!), formatDate(s.fertileEnd!))}',
                    key: const ValueKey('fertile-window'),
                  ),
                ),
              ],
            ),
            const Gap(Space.xs),
            Row(
              children: [
                const Icon(Icons.star, color: AppColors.accent),
                const SizedBox(width: Space.s),
                Expanded(child: Text(l10n.ovulationOn(formatDate(s.ovulation!)))),
              ],
            ),
            const Gap(Space.xs),
            Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.caution),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    '${l10n.riskWindow} : ${l10n.fertileFromTo(formatDate(s.riskStart!), formatDate(s.riskEnd!))}',
                    key: const ValueKey('risk-window'),
                  ),
                ),
              ],
            ),
            const Gap(Space.s),
            Text(l10n.riskHint, style: text.bodySmall),
            if (!reliable) ...[
              const Gap(Space.s),
              Text(l10n.confidenceEstimateHint(calc.cyclesForReliable), style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignalBox extends StatelessWidget {
  const _SignalBox({required this.signal, required this.summary, required this.calc});

  final CycleSignal signal;
  final CycleSummary summary;
  final CycleCalculator calc;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = switch (signal) {
      CycleSignal.shortCycles => l10n.signalShort(calc.shortCycle ?? 0),
      CycleSignal.longCycles => l10n.signalLong(calc.longCycle ?? 0),
      CycleSignal.longPeriod => l10n.signalLongPeriod(calc.longPeriod ?? 0),
      CycleSignal.heavyBleeding => l10n.signalHeavy,
      CycleSignal.amenorrhoea => l10n.signalAmenorrhoea(calc.amenorrhoeaDays ?? 0),
      CycleSignal.late => l10n.signalLate(summary.daysLate),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NoticeBox(
          key: ValueKey('signal-${signal.name}'),
          icon: Icons.warning_amber,
          tone: Tone.warning,
          text: '$message\n${l10n.signalAdvice}',
        ),
        if (signal == CycleSignal.late || signal == CycleSignal.amenorrhoea)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('go-pregnancy'),
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const PregnancyHomeScreen())),
              icon: const Icon(Icons.pregnant_woman),
              label: Text(l10n.goToPregnancy),
            ),
          ),
      ],
    );
  }
}

/// Intensity, symptoms and irregularity of a period, in plain words, for the
/// history list (null when nothing beyond the default was noted).
Widget? _periodSubtitle(AppLocalizations l10n, Period p) {
  final labels = l10n.symptomLabels.split('|');
  final parts = [
    _intensityLabel(l10n, p.intensity),
    for (final (i, code) in periodSymptoms.indexed)
      if (p.symptoms.contains(code)) labels[i],
    if (p.irregular) l10n.periodIrregular,
  ];
  return Text(parts.join(' · '));
}

String _intensityLabel(AppLocalizations l10n, String v) => switch (v) {
  'faible' => l10n.intensityLight,
  'forte' => l10n.intensityHeavy,
  _ => l10n.intensityMedium,
};

/// Bleeding intensity: 1 to 3 drops.
class _IntensityChips extends StatelessWidget {
  const _IntensityChips({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.intensity, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (i, v) in periodIntensities.indexed)
              ChoiceChip(
                key: ValueKey('intensity-$v'),
                showCheckmark: false,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var k = 0; k <= i; k++)
                      const Icon(Icons.water_drop, size: 16, color: AppColors.danger),
                    const SizedBox(width: Space.xs),
                    Text(_intensityLabel(l10n, v)),
                  ],
                ),
                selected: value == v,
                onSelected: (_) => onChanged(v),
              ),
          ],
        ),
      ],
    );
  }
}

/// Symptoms felt during the period, several at once.
class _SymptomChips extends StatelessWidget {
  const _SymptomChips({required this.value, required this.onChanged});

  final Set<String> value;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = l10n.symptomLabels.split('|');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.symptomsTitle, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (i, code) in periodSymptoms.indexed)
              FilterChip(
                key: ValueKey('symptom-$code'),
                label: Text(labels[i]),
                selected: value.contains(code),
                onSelected: (on) => onChanged(on ? {...value, code} : ({...value}..remove(code))),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Règles irrégulières": early, late or unusual.
class _IrregularSwitch extends StatelessWidget {
  const _IrregularSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SwitchListTile(
      key: const ValueKey('period-irregular'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.shuffle, color: AppColors.warning),
      title: Text(l10n.periodIrregular),
      subtitle: Text(l10n.periodIrregularHint),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Flow (3 pictograms), symptoms, pain 0–3, mood (5 face icons) and
/// irregularity of the ongoing period, saved on each tap.
class _TodayDetails extends StatelessWidget {
  const _TodayDetails({required this.period, required this.onChanged});

  final Period period;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final moods = l10n.moodLabels.split('|');
    // Vector faces from Material: same drawing on every phone, unlike emojis
    // whose look depends on the Android version and maker.
    const moodIcons = [
      Icons.sentiment_very_dissatisfied_outlined,
      Icons.sentiment_dissatisfied_outlined,
      Icons.sentiment_neutral_outlined,
      Icons.sentiment_satisfied_outlined,
      Icons.sentiment_very_satisfied_outlined,
    ];
    final scheme = Theme.of(context).colorScheme;
    Future<void> set({
      String? intensity,
      int? pain,
      int? mood,
      Set<String>? symptoms,
      bool? irregular,
    }) async {
      await cycleRepository(context).setDetails(
        period.id,
        intensity: intensity,
        pain: pain,
        mood: mood,
        symptoms: symptoms,
        irregular: irregular,
      );
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IntensityChips(
          value: period.intensity,
          onChanged: (v) => set(intensity: v),
        ),
        const Gap(Space.m),
        _SymptomChips(
          value: period.symptoms,
          onChanged: (v) => set(symptoms: v),
        ),
        const Gap(Space.m),
        Text(l10n.pain, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (var n = 0; n <= 3; n++)
              ChoiceChip(
                key: ValueKey('pain-$n'),
                label: Text('$n', semanticsLabel: l10n.painLevel(n)),
                selected: period.pain == n,
                onSelected: (_) => set(pain: n),
              ),
          ],
        ),
        const Gap(Space.m),
        Text(l10n.mood, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (var m = 1; m <= 5; m++)
              Tooltip(
                message: moods[m - 1],
                child: ChoiceChip(
                  key: ValueKey('mood-$m'),
                  showCheckmark: false,
                  label: Icon(
                    moodIcons[m - 1],
                    size: 28,
                    semanticLabel: moods[m - 1],
                    color: period.mood == m ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  selected: period.mood == m,
                  onSelected: (_) => set(mood: m),
                ),
              ),
          ],
        ),
        const Gap(Space.s),
        _IrregularSwitch(
          value: period.irregular,
          onChanged: (v) => set(irregular: v),
        ),
      ],
    );
  }
}

/// Start and end of a period: a past one to add (e.g. three months ago), or
/// one to correct. Dates are picked with the wheels, never typed.
class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({
    required this.period,
    required this.periods,
    required this.today,
    required this.periodDays,
    this.start,
  });
  final Period? period;

  /// Usual length: the end proposed for a start.
  final int periodDays;

  /// Start already chosen (a day tapped in the calendar).
  final DateTime? start;

  /// Two years back: enough for several past cycles.
  static DateTime firstDay(DateTime today) => addDays(today, -730);
  final List<Period> periods;
  final DateTime today;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late DateTime? _start = widget.period?.start ?? widget.start;
  late DateTime? _end = widget.period?.end;
  late String _intensity = widget.period?.intensity ?? 'moyenne';
  late Set<String> _symptoms = widget.period?.symptoms ?? const {};
  late bool _irregular = widget.period?.irregular ?? false;
  String? _error;

  DateTime get _first => _PeriodSheet.firstDay(widget.today);

  Future<void> _save() async {
    final l10n = context.l10n;
    final start = _start;
    if (start == null) {
      setState(() => _error = l10n.fieldRequired);
      return;
    }
    if (_end != null && _end!.isBefore(start)) {
      setState(() => _error = l10n.endBeforeStart);
      return;
    }
    if (periodOverlaps(widget.periods, start, _end, exceptId: widget.period?.id)) {
      setState(() => _error = l10n.periodOverlap);
      return;
    }
    final navigator = Navigator.of(context);
    final repo = cycleRepository(context);
    final p = widget.period;
    if (p == null) {
      await repo.add(start, _end, intensity: _intensity, symptoms: _symptoms, irregular: _irregular);
    } else {
      await repo.setDates(p.id, start, _end);
      await repo.setDetails(p.id, intensity: _intensity, symptoms: _symptoms, irregular: _irregular);
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.period != null;
    final start = _start;
    // The fields scroll; "Enregistrer" stays pinned under them, above the
    // system navigation bar and the keyboard, on every screen size.
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    editing ? l10n.editPeriod : l10n.periodAddPast,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Gap(Space.m),
                  if (_error != null) ...[
                    NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
                    const Gap(Space.m),
                  ],
                  DateField(
                    key: const ValueKey('period-start-field'),
                    label: l10n.periodStartDate,
                    value: start,
                    first: _first,
                    last: widget.today,
                    onChanged: (d) => setState(() {
                      _start = d;
                      if (_end != null && _end!.isBefore(d)) _end = null;
                      _error = null;
                    }),
                  ),
                  const Gap(Space.m),
                  DateField(
                    key: const ValueKey('period-end-field'),
                    label: l10n.periodEndOptional,
                    value: _end,
                    first: start ?? _first,
                    last: widget.today,
                    initial: start == null ? null : _min(addDays(start, widget.periodDays - 1), widget.today),
                    onChanged: (d) => setState(() {
                      _end = d;
                      _error = null;
                    }),
                    onCleared: () => setState(() => _end = null),
                  ),
                  const Gap(Space.l),
                  _IntensityChips(value: _intensity, onChanged: (v) => setState(() => _intensity = v)),
                  const Gap(Space.m),
                  _SymptomChips(value: _symptoms, onChanged: (v) => setState(() => _symptoms = v)),
                  const Gap(Space.s),
                  _IrregularSwitch(value: _irregular, onChanged: (v) => setState(() => _irregular = v)),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: Space.s),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(key: const ValueKey('period-save'), onPressed: _save, child: Text(l10n.save)),
                  if (editing)
                    TextButton(
                      key: const ValueKey('period-delete'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final ok = await confirmAction(
                          context,
                          message: l10n.deletePeriod,
                          confirmLabel: l10n.delete,
                          destructive: true,
                        );
                        if (!ok || !context.mounted) return;
                        await cycleRepository(context).delete(widget.period!.id);
                        navigator.pop(true);
                      },
                      child: Text(l10n.delete),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
}

/// "Mes règles durent" : the usual length of a period, 3 to 8 days, used for
/// the expected days and to close a period whose end was not noted.
class _PeriodLength extends StatelessWidget {
  const _PeriodLength({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timelapse, color: AppColors.danger),
                const SizedBox(width: Space.s),
                Expanded(child: Text(l10n.periodLengthLabel, style: text.titleSmall)),
              ],
            ),
            const Gap(Space.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  key: const ValueKey('period-days-minus'),
                  tooltip: '${l10n.decrease} – ${l10n.periodLengthLabel}',
                  onPressed: days > periodDaysMin ? () => onChanged(days - 1) : null,
                  icon: const Icon(Icons.remove),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: Text(
                    l10n.periodLengthValue(days),
                    key: const ValueKey('period-days'),
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                ),
                IconButton.outlined(
                  key: const ValueKey('period-days-plus'),
                  tooltip: '${l10n.increase} – ${l10n.periodLengthLabel}',
                  onPressed: days < periodDaysMax ? () => onChanged(days + 1) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const Gap(Space.xs),
            Text(l10n.periodLengthHint, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
