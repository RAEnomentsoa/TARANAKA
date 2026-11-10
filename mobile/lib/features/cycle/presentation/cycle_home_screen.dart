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

/// What "Mon cycle" shows: the periods, the usual length chosen by the user
/// (null: none) and the days noted in "Mon suivi du jour".
typedef _CycleData = ({List<Period> periods, int? setting, List<DayLog> days});

/// "Mon cycle" (spec §4). Outside a period, the main button is "Mes règles
/// ont commencé aujourd'hui" (home → Mon cycle → button: 2 taps). During a
/// period, the card "Mon suivi du jour" offers three clear choices: save the
/// day (the period goes on), the period ended today, or another end date.
class CycleHomeScreen extends StatefulWidget {
  const CycleHomeScreen({super.key});

  @override
  State<CycleHomeScreen> createState() => _CycleHomeScreenState();
}

class _CycleHomeScreenState extends State<CycleHomeScreen> {
  Future<_CycleData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  /// Periods whose end was forgotten are closed at their usual length first,
  /// so they never run over the whole month.
  Future<_CycleData> _load() async {
    final scope = AppScope.read(context);
    final repo = cycleRepository(context);
    final calc = CycleCalculator(scope.services.config.current);
    final today = dateOnly(scope.services.clock.now());
    final setting = await repo.periodDays();
    final periods = await repo.periods();
    await repo.closeForgotten(today, calc.summarise(periods, today, periodDays: setting).periodDays);
    return (periods: await repo.periods(), setting: setting, days: await repo.dayLogs());
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

  Future<void> _openDay(DateTime day, {required bool inPeriod}) async {
    if (await showDaySheet(context, day: day, inPeriod: inPeriod)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final calc = CycleCalculator(config);
    final today = dateOnly(scope.services.clock.now());
    final warning = localizedText(config.cycle['avertissement'], context.lang);

    return FutureBuilder<_CycleData>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: ErrorView(onRetry: _reload));
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (:periods, :setting, :days) = snap.data!;
        final s = calc.summarise(periods, today, periodDays: setting);
        final ongoing = calc.ongoing(periods, today, periodDays: s.periodDays);
        final todayLog = days.where((d) => d.day == today).firstOrNull;
        final outside = [
          for (final d in days)
            if (periodOn(periods, d.day, today) == null) d,
        ];
        final text = Theme.of(context).textTheme;

        return AppScreen(
          title: l10n.tileCycle,
          bottomAction: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Permanent warning (spec §4).
              Padding(
                padding: EdgeInsets.only(bottom: ongoing == null ? Space.s : 0),
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
              // During a period, the three choices sit in "Mon suivi du jour".
              if (ongoing == null)
                FilledButton.icon(
                  key: const ValueKey('period-start-today'),
                  onPressed: () => _startOn(today),
                  icon: const Icon(Icons.water_drop),
                  label: Text(l10n.periodStartedToday),
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
            ],
            _TodayCard(
              // A new state when the period starts or ends, or the day changes.
              key: ValueKey('today-${ongoing?.id}-${isoDate(today)}'),
              period: ongoing,
              today: today,
              log: todayLog,
              onChanged: _reload,
            ),
            const Gap(Space.l),
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
            if (periods.isNotEmpty) ...[
              Text(l10n.periodHistoryHint, style: text.bodySmall),
              const Gap(Space.s),
            ],
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
            // Spotting, mood or pain noted outside a period: still correctable.
            if (outside.isNotEmpty) ...[
              SectionTitle(l10n.daysOutsidePeriods),
              for (final d in outside)
                Card(
                  child: _DayTile(log: d, onTap: () => _openDay(d.day, inPeriod: false)),
                ),
            ],
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

String _flowLabel(AppLocalizations l10n, String v) =>
    v == spottingFlow ? l10n.flowSpotting : _intensityLabel(l10n, v);

/// What was noted on a day, in plain words ("Rien de noté" when nothing).
String _daySummary(AppLocalizations l10n, DayLog? log) {
  if (log == null || log.isEmpty) return l10n.dayNothing;
  final symptoms = l10n.symptomLabels.split('|');
  final pains = l10n.painLabels.split('|');
  final moods = l10n.moodLabels.split('|');
  return [
    if (log.flow != null) _flowLabel(l10n, log.flow!),
    if (log.pain != null) l10n.dayPain(pains[log.pain!.clamp(0, painMax)]),
    if (log.mood != null) l10n.dayMood(moods[(log.mood! - 1).clamp(0, moodMax - 1)]),
    for (final (i, code) in periodSymptoms.indexed)
      if (log.symptoms.contains(code)) symptoms[i],
  ].join(' · ');
}

/// Vector faces from Material: same drawing on every phone, unlike emojis
/// whose look depends on the Android version and maker.
const List<IconData> _moodIcons = [
  Icons.sentiment_very_dissatisfied_outlined,
  Icons.sentiment_dissatisfied_outlined,
  Icons.sentiment_neutral_outlined,
  Icons.sentiment_satisfied_outlined,
  Icons.sentiment_very_satisfied_outlined,
];

/// 1 to 3 drops: the bleeding intensity, never told by the color alone.
class _Drops extends StatelessWidget {
  const _Drops(this.count, {this.outlined = false});

  final int count;
  final bool outlined;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var k = 0; k < count; k++)
          Icon(outlined ? Icons.water_drop_outlined : Icons.water_drop, size: 16, color: AppColors.danger),
      ],
    ),
  );
}

/// One choice of a list (flow, mood): pictogram, short title and a plain
/// explanation under it. Tapping the chosen one again removes the choice.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Material(
        color: selected ? AppColors.accentSoft : AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          side: BorderSide(color: selected ? AppColors.accent : AppColors.outline, width: selected ? 2 : 1),
        ),
        child: Semantics(
          selected: selected,
          inMutuallyExclusiveGroup: true,
          button: true,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Space.touch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
                child: Row(
                  children: [
                    ExcludeSemantics(child: leading),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: text.titleSmall),
                          Text(subtitle, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    ExcludeSemantics(
                      child: Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: selected ? AppColors.accent : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flow of the day: light, medium, heavy (each explained) and, apart,
/// spotting — small blood losses that are not a period. Outside a period only
/// spotting is offered, with a pointer to "Mes règles ont commencé".
class _FlowChoices extends StatelessWidget {
  const _FlowChoices({required this.value, required this.inPeriod, required this.onChanged});

  final String? value;
  final bool inPeriod;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final hints = [l10n.flowLightHint, l10n.flowMediumHint, l10n.flowHeavyHint];
    // A real flow already noted on a day now outside a period stays visible.
    final showFlows = inPeriod || periodIntensities.contains(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.intensity, style: text.titleSmall),
        const Gap(Space.xs),
        if (showFlows) ...[
          for (final (i, v) in periodIntensities.indexed)
            _ChoiceTile(
              key: ValueKey('intensity-$v'),
              leading: _Drops(i + 1),
              title: _intensityLabel(l10n, v),
              subtitle: hints[i],
              selected: value == v,
              onTap: () => onChanged(value == v ? null : v),
            ),
          const Gap(Space.s),
        ],
        _ChoiceTile(
          key: const ValueKey('flow-spotting'),
          leading: const _Drops(1, outlined: true),
          title: l10n.flowSpotting,
          subtitle: l10n.flowSpottingHint,
          selected: value == spottingFlow,
          onTap: () => onChanged(value == spottingFlow ? null : spottingFlow),
        ),
        if (!inPeriod) ...[const Gap(Space.xs), Text(l10n.flowOutsideHint, style: text.bodySmall)],
      ],
    );
  }
}

/// Pain 0–3, each number with its meaning (0 none … 3 strong).
class _PainChoices extends StatelessWidget {
  const _PainChoices({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final labels = l10n.painLabels.split('|');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.pain, style: text.titleSmall),
        Text(l10n.painHint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (var n = 0; n <= painMax; n++)
              ChoiceChip(
                key: ValueKey('pain-$n'),
                label: Text('$n · ${labels[n]}', semanticsLabel: '${l10n.painLevel(n)}, ${labels[n]}'),
                selected: value == n,
                onSelected: (_) => onChanged(value == n ? null : n),
              ),
          ],
        ),
      ],
    );
  }
}

/// Mood: 5 faces, each with its name and a short description.
class _MoodChoices extends StatelessWidget {
  const _MoodChoices({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final moods = l10n.moodLabels.split('|');
    final hints = l10n.moodHints.split('|');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.mood, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.xs),
        for (var m = 1; m <= moodMax; m++)
          _ChoiceTile(
            key: ValueKey('mood-$m'),
            leading: Icon(
              _moodIcons[m - 1],
              size: 32,
              color: value == m ? AppColors.accent : AppColors.textMuted,
            ),
            title: moods[m - 1],
            subtitle: hints[m - 1],
            selected: value == m,
            onTap: () => onChanged(value == m ? null : m),
          ),
      ],
    );
  }
}

/// The fields of one day: flow (or spotting), symptoms, pain, mood.
class _DayFields extends StatelessWidget {
  const _DayFields({required this.value, required this.inPeriod, required this.onChanged});

  final DayLog value;
  final bool inPeriod;
  final ValueChanged<DayLog> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(context.l10n.choiceTapAgain, style: Theme.of(context).textTheme.bodySmall),
      const Gap(Space.m),
      _FlowChoices(
        value: value.flow,
        inPeriod: inPeriod,
        onChanged: (v) => onChanged(value.copyWith(flow: v)),
      ),
      const Gap(Space.l),
      _SymptomChips(
        value: value.symptoms,
        onChanged: (v) => onChanged(value.copyWith(symptoms: v)),
      ),
      const Gap(Space.l),
      _PainChoices(
        value: value.pain,
        onChanged: (v) => onChanged(value.copyWith(pain: v)),
      ),
      const Gap(Space.l),
      _MoodChoices(
        value: value.mood,
        onChanged: (v) => onChanged(value.copyWith(mood: v)),
      ),
    ],
  );
}

/// "Mon suivi du jour". During a period: the day's fields and three choices —
/// save the day (the period goes on), the period ended today, or it ended on
/// another day. Outside a period: mood, pain or spotting, folded by default.
class _TodayCard extends StatefulWidget {
  const _TodayCard({
    super.key,
    required this.period,
    required this.today,
    required this.log,
    required this.onChanged,
  });

  final Period? period;
  final DateTime today;
  final DayLog? log;
  final VoidCallback onChanged;

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> {
  late DayLog _draft = widget.log ?? DayLog(day: widget.today);
  late bool _irregular = widget.period?.irregular ?? false;
  bool _busy = false;

  /// Saves the day (and the irregularity of the period), then [then].
  Future<void> _save(String message, {Future<void> Function(CycleRepository repo, Period p)? then}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = cycleRepository(context);
    final messenger = ScaffoldMessenger.of(context);
    final p = widget.period;
    if (p != null && _irregular != p.irregular) await repo.setDetails(p.id, irregular: _irregular);
    await repo.saveDay(_draft);
    if (p != null && then != null) await then(repo, p);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (mounted) setState(() => _busy = false);
    widget.onChanged();
  }

  Future<void> _endOtherDay() async {
    final l10n = context.l10n;
    final p = widget.period!;
    final picked = await showDateWheel(
      context,
      title: l10n.periodEndDate,
      initial: addDays(widget.today, -1).isBefore(p.start) ? p.start : addDays(widget.today, -1),
      first: p.start,
      last: widget.today,
    );
    if (picked == null || !mounted) return;
    await _save(l10n.periodEndedSaved, then: (repo, p) => repo.end(p.id, picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final inPeriod = widget.period != null;
    final fields = _DayFields(
      value: _draft,
      inPeriod: inPeriod,
      onChanged: (v) => setState(() => _draft = v),
    );
    final saveButton = FilledButton.icon(
      key: const ValueKey('day-save'),
      onPressed: _busy ? null : () => _save(l10n.daySaved),
      icon: const Icon(Icons.save_outlined),
      label: Text(l10n.daySave),
    );

    if (!inPeriod) {
      return Card(
        child: ExpansionTile(
          key: const ValueKey('day-follow-up'),
          initiallyExpanded: widget.log != null,
          leading: const Icon(Icons.edit_calendar_outlined, color: AppColors.accent),
          title: Text(l10n.dayFollowUpTitle, style: text.titleMedium),
          subtitle: Text(l10n.dayFollowUpOutsideHint),
          shape: const Border(),
          childrenPadding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [fields, const Gap(Space.l), saveButton],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_calendar_outlined, color: AppColors.accent),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Semantics(header: true, child: Text(l10n.dayFollowUpTitle, style: text.titleMedium)),
                ),
              ],
            ),
            const Gap(Space.xs),
            Text(l10n.dayFollowUpHint, style: text.bodySmall),
            const Gap(Space.m),
            fields,
            const Gap(Space.s),
            _IrregularSwitch(value: _irregular, onChanged: (v) => setState(() => _irregular = v)),
            const Gap(Space.l),
            // 1. The period goes on (main action).
            saveButton,
            const Gap(Space.s),
            // 2. Last day of the period.
            OutlinedButton.icon(
              key: const ValueKey('period-end-today'),
              onPressed: _busy
                  ? null
                  : () => _save(l10n.periodEndedSaved, then: (repo, p) => repo.end(p.id, widget.today)),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(l10n.periodEndedToday),
            ),
            const Gap(Space.xs),
            // 3. It ended on an earlier day.
            TextButton.icon(
              key: const ValueKey('period-end-other-day'),
              onPressed: _busy ? null : _endOtherDay,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(l10n.periodEndOtherDay),
            ),
          ],
        ),
      ),
    );
  }
}

/// A noted day in a list: date and what was noted; opens it for correction.
class _DayTile extends StatelessWidget {
  const _DayTile({required this.log, required this.onTap, this.day});

  final DayLog? log;

  /// The day when nothing is noted yet ([log] null).
  final DateTime? day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = log?.day ?? day!;
    final noted = log != null && !log!.isEmpty;
    return ListTile(
      key: ValueKey('day-${isoDate(d)}'),
      leading: Icon(
        log?.isSpotting ?? false ? Icons.water_drop_outlined : Icons.event_note_outlined,
        color: noted ? AppColors.danger : AppColors.textMuted,
      ),
      title: Text(formatDate(d)),
      subtitle: Text(_daySummary(l10n, log)),
      trailing: Icon(Icons.edit_outlined, semanticLabel: l10n.editPeriod),
      onTap: onTap,
    );
  }
}

/// Opens the follow-up of [day] to review or correct it. True when changed.
Future<bool> showDaySheet(BuildContext context, {required DateTime day, required bool inPeriod}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DaySheet(day: day, inPeriod: inPeriod),
    ) ==
    true;

class _DaySheet extends StatefulWidget {
  const _DaySheet({required this.day, required this.inPeriod});

  final DateTime day;
  final bool inPeriod;

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  Future<DayLog?>? _loaded;
  DayLog? _draft;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loaded ??= cycleRepository(context).dayLog(widget.day);
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    await cycleRepository(context).saveDay(_draft!);
    navigator.pop(true);
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final repo = cycleRepository(context);
    final ok = await confirmAction(
      context,
      message: l10n.dayDeleteConfirm,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!ok) return;
    await repo.deleteDay(widget.day);
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    return FutureBuilder<DayLog?>(
      future: _loaded,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(Space.xl), child: LoadingView());
        }
        final existing = snap.data;
        final draft = _draft ??= existing ?? DayLog(day: widget.day);
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.dayLogTitle(formatDate(widget.day)),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Gap(Space.m),
                      _DayFields(
                        value: draft,
                        inPeriod: widget.inPeriod,
                        onChanged: (v) => setState(() => _draft = v),
                      ),
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
                      FilledButton(
                        key: const ValueKey('day-sheet-save'),
                        onPressed: _save,
                        child: Text(l10n.save),
                      ),
                      if (existing != null)
                        TextButton(
                          key: const ValueKey('day-sheet-delete'),
                          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                          onPressed: _delete,
                          child: Text(l10n.delete),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Bleeding intensity of a whole past period: 1 to 3 drops.
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

/// Start and end of a period: a past one to add (e.g. three months ago), or
/// one to correct, with its follow-up day by day (each day can be reviewed
/// and corrected, even after the end). Dates are picked with the wheels.
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

  /// Days of the period being corrected and what was noted on each.
  List<DayLog>? _days;

  DateTime get _first => _PeriodSheet.firstDay(widget.today);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.period != null && _days == null) _loadDays();
  }

  /// Last day of the period being corrected (an ongoing one: today).
  DateTime get _lastDay {
    final end = widget.period!.end ?? widget.today;
    return end.isAfter(widget.today) ? widget.today : end;
  }

  Future<void> _loadDays() async {
    final days = await cycleRepository(context).dayLogs(from: widget.period!.start, to: _lastDay);
    if (mounted) setState(() => _days = days);
  }

  Future<void> _openDay(DateTime day) async {
    if (await showDaySheet(context, day: day, inPeriod: true)) await _loadDays();
  }

  /// Flow and symptoms of the whole period: only when no day was noted
  /// (otherwise they come from the days).
  bool get _periodDetails => widget.period == null || (_days?.isEmpty ?? false);

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
      await repo.setDetails(
        p.id,
        intensity: _periodDetails ? _intensity : null,
        symptoms: _periodDetails ? _symptoms : null,
        irregular: _irregular,
      );
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
                  if (_periodDetails) ...[
                    _IntensityChips(value: _intensity, onChanged: (v) => setState(() => _intensity = v)),
                    const Gap(Space.m),
                    _SymptomChips(value: _symptoms, onChanged: (v) => setState(() => _symptoms = v)),
                    const Gap(Space.s),
                  ],
                  _IrregularSwitch(value: _irregular, onChanged: (v) => setState(() => _irregular = v)),
                  if (editing) ..._dayByDay(context),
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

  /// "Suivi jour par jour": every day of the period, most recent first.
  List<Widget> _dayByDay(BuildContext context) {
    final l10n = context.l10n;
    final days = _days;
    final start = widget.period!.start;
    final count = daysBetween(start, _lastDay) + 1;
    return [
      SectionTitle(l10n.dayHistoryTitle),
      Text(l10n.dayHistoryHint, style: Theme.of(context).textTheme.bodySmall),
      const Gap(Space.s),
      if (days == null)
        const LinearProgressIndicator()
      else
        for (var i = count - 1; i >= 0; i--)
          Builder(
            builder: (context) {
              final day = addDays(start, i);
              return _DayTile(
                log: days.where((d) => d.day == day).firstOrNull,
                day: day,
                onTap: () => _openDay(day),
              );
            },
          ),
    ];
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
