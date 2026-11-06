import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cores/l10n/labels.dart';
import '../../cores/providers/cycle_providers.dart';
import '../../cores/providers/language_provider.dart';
import '../../cores/services/cycle_timeline.dart';
import '../components/language_switcher.dart';
import 'cycle_advice_view.dart';
import 'cycle_history_view.dart';
import 'cycle_today_view.dart';

/// Section « Mes règles » : roue et saisie, calendrier, conseils.
class CyclePage extends ConsumerStatefulWidget {
  const CyclePage({super.key});

  @override
  ConsumerState<CyclePage> createState() => _CyclePageState();
}

class _CyclePageState extends ConsumerState<CyclePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(language.pick(mg: 'Ny fadimbolanako', fr: 'Mes règles')),
        ),
        actions: const [LanguageSwitcher()],
      ),
      body: SafeArea(
        child: switch (_tab) {
          0 => const _WithTimeline(builder: _today),
          1 => const _WithTimeline(builder: _history),
          _ => const CycleAdviceView(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
        destinations: [
          NavigationDestination(
            icon: const Icon(Symbols.water_drop),
            label: language.pick(mg: 'Tsingerina', fr: 'Mon cycle'),
          ),
          NavigationDestination(
            icon: const Icon(Symbols.calendar_month),
            label: language.pick(mg: 'Tetiandro', fr: 'Calendrier'),
          ),
          NavigationDestination(
            icon: const Icon(Symbols.info),
            label: language.pick(mg: 'Torohevitra', fr: 'Conseils'),
          ),
        ],
      ),
    );
  }

  static Widget _today(CycleTimeline timeline) =>
      CycleTodayView(timeline: timeline);

  static Widget _history(CycleTimeline timeline) =>
      CycleHistoryView(timeline: timeline);
}

/// Attend l'historique, et signale l'échec de sa lecture.
class _WithTimeline extends ConsumerWidget {
  const _WithTimeline({required this.builder});

  final Widget Function(CycleTimeline timeline) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return ref
        .watch(cycleTimelineProvider)
        .when(
          data: builder,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                language.pick(
                  mg: 'Tsy azo vakina ny tantara.',
                  fr: 'Impossible de lire l’historique.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
  }
}
