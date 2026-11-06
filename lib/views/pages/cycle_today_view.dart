import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cores/l10n/labels.dart';
import '../../cores/providers/cycle_providers.dart';
import '../../cores/providers/language_provider.dart';
import '../../cores/services/cycle_timeline.dart';
import '../../cores/services/days.dart';
import '../../cores/themes/app_colors.dart';
import '../components/cycle_wheel.dart';
import '../components/period_form.dart';
import '../components/phase_style.dart';

/// Menu 1 : roue du cycle et saisie.
class CycleTodayView extends ConsumerWidget {
  const CycleTodayView({super.key, required this.timeline});

  final CycleTimeline timeline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final today = dayOf(ref.watch(clockProvider)());
    final textTheme = Theme.of(context).textTheme;

    final days = timeline.currentCycleDays(today);
    final upcomingStart = timeline.upcomingStartOn(today);
    final cycleDay = timeline.cycleDayOn(today);
    final lateDays = timeline.lateDaysOn(today);
    final todayIndex = cycleDay == null
        ? null
        : (cycleDay - 1).clamp(0, days.length - 1);
    final phase = lateDays > 0 ? null : timeline.markOn(today, today)?.phase;

    // Pas de ListView : il détruirait hors écran le formulaire et sa saisie.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CycleWheel(
            days: days,
            todayIndex: todayIndex,
            semanticLabel: _wheelDescription(
              language,
              upcomingStart,
              cycleDay,
              phase,
              lateDays,
            ),
            center: _WheelCenter(
              upcomingStart: upcomingStart,
              language: language,
              cycleDay: cycleDay,
              phase: phase,
              lateDays: lateDays,
            ),
          ),
          const SizedBox(height: 12),
          PhaseLegend(language: language),
          if (!timeline.isEmpty) ...[
            const SizedBox(height: 16),
            _Forecast(language: language, timeline: timeline, today: today),
          ],
          const SizedBox(height: 24),
          Text(
            language.pick(
              mg: 'Nanomboka ve ny fadimbolanao?',
              fr: 'Vos règles ont commencé ?',
            ),
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          PeriodForm(
            timeline: timeline,
            onSaved: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  language.pick(mg: 'Voatahiry.', fr: 'Enregistré.'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _wheelDescription(
    AppLanguage language,
    DateTime? upcomingStart,
    int? cycleDay,
    CyclePhase? phase,
    int lateDays,
  ) {
    if (upcomingStart != null) return _upcomingText(language, upcomingStart);
    if (cycleDay == null) {
      return language.pick(
        mg: 'Kodiaran’ny tsingerina: mbola tsy misy daty voarakitra.',
        fr: 'Roue du cycle : aucune date enregistrée.',
      );
    }
    return [
      language.pick(
        mg: 'Kodiaran’ny tsingerina: andro faha-$cycleDay.',
        fr: 'Roue du cycle : jour $cycleDay.',
      ),
      if (phase != null) language.phaseName(phase),
      if (lateDays > 0) _lateText(language, lateDays),
    ].join(' ');
  }
}

String _lateText(AppLanguage language, int lateDays) => language.pick(
  mg: 'Tara ${language.formatDays(lateDays)}',
  fr: 'Retard de ${language.formatDays(lateDays)}',
);

String _upcomingText(AppLanguage language, DateTime start) => language.pick(
  mg: 'Hanomboka ny ${language.formatDate(start)}',
  fr: 'Début le ${language.formatDate(start)}',
);

class _WheelCenter extends StatelessWidget {
  const _WheelCenter({
    required this.upcomingStart,
    required this.language,
    required this.cycleDay,
    required this.phase,
    required this.lateDays,
  });

  final AppLanguage language;
  final DateTime? upcomingStart;
  final int? cycleDay;
  final CyclePhase? phase;
  final int lateDays;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cycleDay = this.cycleDay;
    final phase = this.phase;
    final upcomingStart = this.upcomingStart;

    if (upcomingStart != null) {
      return Text(
        _upcomingText(language, upcomingStart),
        textAlign: TextAlign.center,
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      );
    }

    if (cycleDay == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Symbols.menstrual_health,
              size: 40,
              color: AppColors.primaryDark,
            ),
            const SizedBox(height: 8),
            Text(
              language.pick(
                mg: 'Ampidiro eto ambany ny daty nanombohan’ny fadimbolanao',
                fr: 'Saisissez ci-dessous la date de début de vos règles',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          language.pick(mg: 'Andro faha-', fr: 'Jour'),
          style: textTheme.titleMedium,
        ),
        Text(
          '$cycleDay',
          style: textTheme.displayMedium?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (phase != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                phase.icon,
                size: 20,
                // Le bleu et l'orange clairs ressortent mal sur le fond blanc.
                color: phase.onColor == AppColors.white
                    ? phase.color
                    : AppColors.ink,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  language.phaseName(phase),
                  textAlign: TextAlign.center,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        if (lateDays > 0)
          Text(
            _lateText(language, lateDays),
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _Forecast extends StatelessWidget {
  const _Forecast({
    required this.language,
    required this.timeline,
    required this.today,
  });

  final AppLanguage language;
  final CycleTimeline timeline;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final nextStart = timeline.nextStartOn(today)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            _ForecastLine(
              icon: CyclePhase.menstruation.icon,
              iconColor: AppColors.menstruation,
              label: language.pick(
                mg: 'Fadimbolana manaraka',
                fr: 'Prochaines règles',
              ),
              value: language.formatDate(nextStart),
            ),
            _ForecastLine(
              icon: CyclePhase.ovulation.icon,
              iconColor: AppColors.ovulation,
              label: language.pick(mg: 'Ovulation', fr: 'Ovulation'),
              value: language.formatDate(timeline.ovulationBefore(nextStart)!),
            ),
            Text(
              language.pick(
                mg:
                    'Vinavina fotsiny ireo daty ireo, ary tsy fomba '
                    'fanabeazana aizana.',
                fr:
                    'Ces dates sont indicatives et ne constituent pas une '
                    'méthode de contraception.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastLine extends StatelessWidget {
  const _ForecastLine({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}
