import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cores/l10n/labels.dart';
import '../../cores/models/cycle.dart';
import '../../cores/providers/cycle_providers.dart';
import '../../cores/providers/language_provider.dart';
import '../../cores/services/cycle_timeline.dart';
import '../../cores/services/days.dart';
import '../../cores/themes/app_colors.dart';
import '../components/month_calendar.dart';
import '../components/period_form.dart';
import '../components/phase_style.dart';

/// Menu 2 : calendrier, métriques et historique.
class CycleHistoryView extends ConsumerStatefulWidget {
  const CycleHistoryView({super.key, required this.timeline});

  final CycleTimeline timeline;

  @override
  ConsumerState<CycleHistoryView> createState() => _CycleHistoryViewState();
}

class _CycleHistoryViewState extends ConsumerState<CycleHistoryView> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final today = dayOf(ref.watch(clockProvider)());
    final timeline = widget.timeline;
    final selected = _selected ?? today;

    // Le calendrier occupe toute la largeur : sur un écran de 320 px, c'est ce
    // qui garantit des cellules de plus de 44 px.
    Widget padded(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          padded(
            _Metrics(language: language, timeline: timeline, today: today),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: MonthCalendar(
              language: language,
              today: today,
              selected: selected,
              markOf: (day) => timeline.markOn(day, today),
              expectedDay: timeline.storedEstimate,
              onDaySelected: (day) => setState(() => _selected = day),
            ),
          ),
          const SizedBox(height: 12),
          padded(
            _SelectedDay(
              language: language,
              day: selected,
              mark: timeline.markOn(selected, today),
              isExpected: selected == timeline.storedEstimate,
            ),
          ),
          const SizedBox(height: 12),
          padded(PhaseLegend(language: language)),
          const SizedBox(height: 8),
          padded(
            Text(
              language.pick(
                mg:
                    'Ny andro misy sisiny miloko fotsiny dia vinavina. Ny saina '
                    'dia manamarika ny fadimbolana andrasana.',
                fr:
                    'Les jours seulement bordés de couleur sont des prévisions. '
                    'Le drapeau marque les prochaines règles attendues.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
          padded(
            Text(
              language.pick(mg: 'Tantara', fr: 'Historique'),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          if (timeline.isEmpty)
            padded(
              Text(
                language.pick(
                  mg: 'Mbola tsy misy daty voarakitra.',
                  fr: 'Aucun cycle enregistré pour le moment.',
                ),
              ),
            )
          else
            for (final (index, cycle)
                in timeline.cycles.indexed.toList().reversed)
              padded(
                _HistoryEntry(
                  language: language,
                  cycle: cycle,
                  elapsedLength: index < timeline.elapsedLengths.length
                      ? timeline.elapsedLengths[index]
                      : null,
                  onEdit: () => _edit(language, cycle),
                  onDelete: () => _delete(language, cycle),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _edit(AppLanguage language, Cycle cycle) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              20,
              16,
              16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: PeriodForm(
              timeline: widget.timeline,
              initial: cycle,
              onSaved: () => Navigator.pop(sheetContext),
            ),
          ),
        ),
      );

  Future<void> _delete(AppLanguage language, Cycle cycle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          language.pick(mg: 'Hofafana ve?', fr: 'Supprimer ce cycle ?'),
        ),
        content: Text(language.formatDate(parseDay(cycle.dateDebut)!)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(language.pick(mg: 'Tsia', fr: 'Annuler')),
          ),
          TextButton(
            key: const ValueKey('cycle-delete-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.warning),
            child: Text(language.pick(mg: 'Fafao', fr: 'Supprimer')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(cycleJournalProvider).remove(cycle.id!);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            language.pick(
              mg: 'Tsy voafafa. Andramo indray.',
              fr: 'Suppression impossible. Veuillez réessayer.',
            ),
          ),
        ),
      );
    }
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.language,
    required this.timeline,
    required this.today,
  });

  final AppLanguage language;
  final CycleTimeline timeline;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final nextStart = timeline.nextStartOn(today);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _Metric(
              icon: Symbols.timelapse,
              label: language.pick(
                mg: 'Faharetana antonony',
                fr: 'Durée moyenne des cycles',
              ),
              value: timeline.isEmpty
                  ? '—'
                  : language.formatDays(timeline.averageLength),
            ),
            _Metric(
              icon: Symbols.monitoring,
              label: language.pick(mg: 'Fitoviana', fr: 'Régularité'),
              value: language.regularityName(timeline.regularity),
            ),
            _Metric(
              icon: Symbols.event_upcoming,
              label: language.pick(
                mg: 'Fadimbolana manaraka (vinavina)',
                fr: 'Prochaines règles (estimation)',
              ),
              value: nextStart == null ? '—' : language.formatDate(nextStart),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDay extends StatelessWidget {
  const _SelectedDay({
    required this.language,
    required this.day,
    required this.mark,
    required this.isExpected,
  });

  final AppLanguage language;
  final DateTime day;
  final DayMark? mark;
  final bool isExpected;

  @override
  Widget build(BuildContext context) {
    final mark = this.mark;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(mark?.phase.icon ?? Symbols.event, color: AppColors.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                language.formatDate(day),
                if (mark != null) language.phaseName(mark.phase),
                if (mark != null && mark.forecast)
                  language.pick(mg: '(vinavina)', fr: '(prévision)'),
                if (isExpected) language.expectedPeriodName,
              ].join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({
    required this.language,
    required this.cycle,
    required this.elapsedLength,
    required this.onEdit,
    required this.onDelete,
  });

  final AppLanguage language;
  final Cycle cycle;

  /// Durée réelle ; `null` pour le cycle en cours.
  final int? elapsedLength;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final end = parseDay(cycle.dateFin);
    final intensity = cycle.intensite;
    final elapsedLength = this.elapsedLength;
    final details = [
      if (end != null)
        language.pick(
          mg: 'Hatramin’ny ${language.formatDate(end)}',
          fr: 'Jusqu’au ${language.formatDate(end)}',
        ),
      if (elapsedLength != null)
        language.pick(
          mg: 'Tsingerina: ${language.formatDays(elapsedLength)}',
          fr: 'Cycle : ${language.formatDays(elapsedLength)}',
        )
      else
        language.pick(mg: 'Tsingerina ankehitriny', fr: 'Cycle en cours'),
      if (cycle.dureRegle case final periodLength?)
        language.pick(
          mg: 'Fadimbolana: ${language.formatDays(periodLength)}',
          fr: 'Règles : ${language.formatDays(periodLength)}',
        ),
      if (intensity != null)
        '${language.pick(mg: 'Habetsahan’ny rà', fr: 'Intensité')} : '
            '${language.intensityName(intensity)}',
      ...PeriodSymptom.decode(cycle.symptome).map(language.symptomName),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language.formatDate(parseDay(cycle.dateDebut)!),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(details.join(' · ')),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('cycle-edit-${cycle.id}'),
              onPressed: onEdit,
              tooltip: language.pick(mg: 'Ovay', fr: 'Modifier'),
              icon: const Icon(Symbols.edit, color: AppColors.primaryDark),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            IconButton(
              key: ValueKey('cycle-delete-${cycle.id}'),
              onPressed: onDelete,
              tooltip: language.pick(mg: 'Fafao', fr: 'Supprimer'),
              icon: const Icon(Symbols.delete, color: AppColors.warning),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ],
        ),
      ),
    );
  }
}
