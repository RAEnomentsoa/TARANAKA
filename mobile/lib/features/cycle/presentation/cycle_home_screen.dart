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
  Future<List<Period>>? _periods;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _periods ??= cycleRepository(context).periods();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _periods = cycleRepository(context).periods();
    });
  }

  Future<void> _startOn(DateTime day) async {
    await cycleRepository(context).start(day);
    _reload();
  }

  /// Adds a past period ([period] null) or edits one.
  Future<void> _openSheet(Period? period, List<Period> periods, DateTime today, {DateTime? start}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PeriodSheet(period: period, periods: periods, today: today, start: start),
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

    return FutureBuilder<List<Period>>(
      future: _periods,
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: ErrorView(onRetry: _reload));
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final periods = snap.data!;
        final s = calc.summarise(periods, today);
        final ongoing = calc.ongoing(periods, today);
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
              onPeriodTap: (p) => _openSheet(p, periods, today),
              onDayTap: (d) => _openSheet(null, periods, today, start: d),
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
            SectionTitle(l10n.periodHistory),
            OutlinedButton.icon(
              key: const ValueKey('period-add-past'),
              onPressed: () => _openSheet(null, periods, today),
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
                  trailing: Icon(Icons.edit_outlined, semanticLabel: l10n.editPeriod),
                  onTap: () => _openSheet(p, periods, today),
                ),
              ),
            const Gap(Space.l),
            Text(l10n.cycleLocal, style: text.bodySmall),
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
    if (s.nextPeriod == null) {
      return NoticeBox(icon: Icons.insights_outlined, text: l10n.noPrediction);
    }
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

/// Flow (3 pictograms), pain 0–3, mood (5 emojis) for the ongoing period.
class _TodayDetails extends StatelessWidget {
  const _TodayDetails({required this.period, required this.onChanged});

  final Period period;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final moods = l10n.moodLabels.split('|');
    const emojis = ['😢', '🙁', '😐', '🙂', '😄'];
    Future<void> set({String? intensity, int? pain, int? mood}) async {
      await cycleRepository(context).setDetails(period.id, intensity: intensity, pain: pain, mood: mood);
      onChanged();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.intensity, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (i, v, label) in [
              (1, 'faible', l10n.intensityLight),
              (2, 'moyenne', l10n.intensityMedium),
              (3, 'forte', l10n.intensityHeavy),
            ])
              ChoiceChip(
                key: ValueKey('intensity-$v'),
                showCheckmark: false,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var k = 0; k < i; k++)
                      const Icon(Icons.water_drop, size: 16, color: AppColors.danger),
                    const SizedBox(width: Space.xs),
                    Text(label),
                  ],
                ),
                selected: period.intensity == v,
                onSelected: (_) => set(intensity: v),
              ),
          ],
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
                  label: Text(
                    emojis[m - 1],
                    semanticsLabel: moods[m - 1],
                    style: const TextStyle(fontSize: 22),
                  ),
                  selected: period.mood == m,
                  onSelected: (_) => set(mood: m),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Start and end of a period: a past one to add (e.g. three months ago), or
/// one to correct. Dates are picked with the wheels, never typed.
class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.period, required this.periods, required this.today, this.start});
  final Period? period;

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
    p == null ? await repo.add(start, _end) : await repo.setDates(p.id, start, _end);
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.period != null;
    final start = _start;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, MediaQuery.viewInsetsOf(context).bottom + Space.l),
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
            initial: start == null ? null : _min(addDays(start, 4), widget.today),
            onChanged: (d) => setState(() {
              _end = d;
              _error = null;
            }),
            onCleared: () => setState(() => _end = null),
          ),
          const Gap(Space.l),
          FilledButton(key: const ValueKey('period-save'), onPressed: _save, child: Text(l10n.save)),
          if (editing) ...[
            const Gap(Space.s),
            TextButton(
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
        ],
      ),
    );
  }

  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
}
