import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../agent/domain/screening.dart';
import '../data/child_repository.dart';
import '../domain/feeding.dart';
import 'my_children_screen.dart';

/// Feeding by age (spec §6): exclusive breastfeeding for 0–5 months, food
/// diary by pictograms for 6–23 months, with the WHO/UNICEF indicators and
/// advice from the validated library. Saved on every tap.
class FeedingScreen extends StatefulWidget {
  const FeedingScreen({super.key, required this.childId});
  final String childId;

  @override
  State<FeedingScreen> createState() => _FeedingScreenState();
}

class _FeedingScreenState extends State<FeedingScreen> {
  MyChild? _child;
  late DateTime _day;
  FeedingLog? _log;
  List<FeedingLog> _week = const [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _day = dateOnly(AppScope.read(context).services.clock.now());
    _load();
  }

  Future<void> _load() async {
    final repo = childRepository(context);
    final child = await repo.child(widget.childId);
    final log = await repo.feeding(widget.childId, _day);
    final week = await repo.feedingSince(widget.childId, _day.subtract(const Duration(days: 6)));
    if (!mounted) return;
    setState(() {
      _child = child;
      _log = log;
      _week = week;
    });
  }

  Future<void> _save(FeedingLog log) async {
    setState(() => _log = log);
    final repo = childRepository(context);
    await repo.saveFeeding(widget.childId, log);
    final week = await repo.feedingSince(widget.childId, _day.subtract(const Duration(days: 6)));
    if (mounted) setState(() => _week = week);
  }

  FeedingLog get _current =>
      _log ?? FeedingLog(date: _day, breastfeeding: 'aucun', foods: const {}, meals: 0, milkFeeds: 0);

  void _move(int days) {
    setState(() {
      _day = _day.add(Duration(days: days));
      _log = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final child = _child;
    if (child == null) return const Scaffold(body: LoadingView());
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final today = dateOnly(scope.services.clock.now());
    final rules = FeedingRules(config);
    final days = ScreeningCalculator.ageDays(child.birthDate, _day);
    final months = days < 0 ? 0 : ScreeningCalculator.ageMonths(days);
    final exclusiveAge = months <= rules.exclusiveMaxMonths;
    final diaryAge = months >= rules.logMinMonths && months <= rules.logMaxMonths;

    final summary = diaryAge && !exclusiveAge
        ? rules.compute(
            ageMonths: months,
            day: FeedingDay(foods: _current.foods, meals: _current.meals, milkFeeds: _current.milkFeeds),
          )
        : null;
    return AppScreen(
      title: '${exclusiveAge ? l10n.breastfeeding : l10n.feeding} – ${child.name}',
      // Always visible while tapping foods: the score changes at each tap.
      bottomAction: summary == null
          ? null
          : Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(Radii.m),
                  border: Border.all(color: AppColors.accentSoftBorder),
                ),
                child: LabelWithPill(
                  label: Text(
                    l10n.diversityScore(summary.groupCount, summary.groupTotal),
                    key: const ValueKey('diversity-summary'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  pill: StatusPill(
                    icon: summary.diversityMet ? Icons.check_circle_outline : Icons.error_outline,
                    label: summary.diversityMet ? l10n.diversityOk : l10n.diversityLow,
                    tone: summary.diversityMet ? Tone.success : Tone.warning,
                  ),
                ),
              ),
            ),
      children: [
        _DayPicker(
          day: _day,
          isToday: _day == today,
          canGoForward: _day.isBefore(today),
          canGoBack: _day.isAfter(child.birthDate),
          onMove: _move,
        ),
        const Gap(Space.l),
        if (exclusiveAge)
          ..._breastfeeding(context)
        else if (diaryAge)
          ..._diary(context, rules, months, config)
        else
          NoticeBox(icon: Icons.info_outline, text: l10n.feedingNotInRange),
        if (_log != null) ...[
          const Gap(Space.l),
          const Align(alignment: Alignment.centerLeft, child: SyncStatusPill(SyncStatus.saved)),
        ],
      ],
    );
  }

  List<Widget> _breastfeeding(BuildContext context) {
    final l10n = context.l10n;
    final log = _current;
    final exclusive = _log?.breastfeeding == 'exclusif';
    final notExclusive = _log != null && _log!.breastfeeding != 'exclusif';
    final exclusiveDays = _week.where((l) => l.breastfeeding == 'exclusif').length;
    return [
      Text(l10n.exclusiveQuestion, style: Theme.of(context).textTheme.titleMedium),
      const Gap(Space.m),
      _ChoiceButton(
        key: const ValueKey('exclusive-yes'),
        selected: exclusive,
        icon: Icons.check_circle_outline,
        label: l10n.exclusiveYes,
        onTap: () => _save(
          FeedingLog(
            date: _day,
            breastfeeding: 'exclusif',
            foods: const {},
            meals: 0,
            milkFeeds: 0,
            breastFeeds: log.breastFeeds,
          ),
        ),
      ),
      const Gap(Space.s),
      _ChoiceButton(
        key: const ValueKey('exclusive-no'),
        selected: notExclusive,
        icon: Icons.cancel_outlined,
        label: l10n.exclusiveNo,
        onTap: () => _save(
          FeedingLog(
            date: _day,
            breastfeeding: 'mixte',
            foods: const {},
            meals: 0,
            milkFeeds: 0,
            breastFeeds: log.breastFeeds,
          ),
        ),
      ),
      const Gap(Space.l),
      _Counter(
        label: l10n.breastFeedsCount,
        value: log.breastFeeds ?? 0,
        onChanged: (v) => _save(
          FeedingLog(
            date: _day,
            breastfeeding: _log?.breastfeeding ?? 'exclusif',
            foods: const {},
            meals: 0,
            milkFeeds: 0,
            breastFeeds: v,
          ),
        ),
      ),
      const Gap(Space.l),
      NoticeBox(icon: Icons.insights_outlined, text: l10n.exclusiveLast7(exclusiveDays)),
      const Gap(Space.m),
      NoticeBox(icon: Icons.lightbulb_outline, text: l10n.exclusiveAdvice),
    ];
  }

  List<Widget> _diary(BuildContext context, FeedingRules rules, int months, ClinicalConfig config) {
    final l10n = context.l10n;
    final lang = context.lang;
    final log = _current;
    final indicators = rules.compute(
      ageMonths: months,
      day: FeedingDay(foods: log.foods, meals: log.meals, milkFeeds: log.milkFeeds),
    );
    FeedingLog next({Set<String>? foods, int? meals, int? milk}) {
      final f = foods ?? log.foods;
      return FeedingLog(
        date: _day,
        breastfeeding: f.contains('lait_maternel') ? 'mixte' : 'aucun',
        foods: f,
        meals: meals ?? log.meals,
        milkFeeds: milk ?? log.milkFeeds,
      );
    }

    final groupsByNumber = {for (final g in rules.groups) g.number: g};
    return [
      Text(l10n.tapFoods, style: Theme.of(context).textTheme.titleMedium),
      const Gap(Space.m),
      Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        children: [
          for (final f in rules.foods)
            FilterChip(
              key: ValueKey('food-${f.code}'),
              avatar: Icon(_groupIcon(f.group), size: 20, color: AppColors.accent),
              label: Text(_foodLabel(f, lang)),
              tooltip: localizedText(groupsByNumber[f.group]?.labels, lang),
              selected: log.foods.contains(f.code),
              onSelected: (v) {
                final foods = {...log.foods};
                v ? foods.add(f.code) : foods.remove(f.code);
                _save(next(foods: foods));
              },
            ),
        ],
      ),
      const Gap(Space.l),
      _Counter(
        label: l10n.mealsCount,
        value: log.meals,
        onChanged: (v) => _save(next(meals: v)),
      ),
      if (!indicators.breastfed) ...[
        const Gap(Space.s),
        _Counter(
          label: l10n.milkFeedsCount,
          value: log.milkFeeds,
          onChanged: (v) => _save(next(milk: v)),
        ),
      ],
      const Gap(Space.l),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabelWithPill(
                label: Text(
                  l10n.diversityScore(indicators.groupCount, indicators.groupTotal),
                  key: const ValueKey('diversity-score'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                pill: StatusPill(
                  icon: indicators.diversityMet ? Icons.check_circle_outline : Icons.error_outline,
                  label: indicators.diversityMet ? l10n.diversityOk : l10n.diversityLow,
                  tone: indicators.diversityMet ? Tone.success : Tone.warning,
                ),
              ),
              const Gap(Space.s),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xs,
                children: [
                  for (final g in rules.groups)
                    Tooltip(
                      message: localizedText(g.labels, lang),
                      child: Icon(
                        _groupIcon(g.number),
                        color: indicators.groups.contains(g.number) ? AppColors.accent : AppColors.outline,
                        semanticLabel:
                            '${localizedText(g.labels, lang)}: ${indicators.groups.contains(g.number) ? l10n.yes : l10n.no}',
                      ),
                    ),
                ],
              ),
              if (indicators.mealsRequired != null) ...[
                const Gap(Space.m),
                Row(
                  children: [
                    Expanded(child: Text(l10n.mealsScore(log.meals, indicators.mealsRequired!))),
                    Icon(
                      indicators.mealsMet ? Icons.check_circle_outline : Icons.error_outline,
                      color: indicators.mealsMet ? AppColors.success : AppColors.warning,
                    ),
                  ],
                ),
              ],
              const Gap(Space.s),
              LabelWithPill(
                label: Text(l10n.acceptableDiet),
                pill: StatusPill(
                  icon: indicators.acceptableMet ? Icons.check : Icons.close,
                  label: indicators.acceptableMet ? l10n.yes : l10n.no,
                  tone: indicators.acceptableMet ? Tone.success : Tone.warning,
                ),
              ),
            ],
          ),
        ),
      ),
      for (final a in indicators.advice) ...[
        const Gap(Space.m),
        NoticeBox(
          key: ValueKey('advice-${a.code}'),
          icon: Icons.lightbulb_outline,
          title: l10n.adviceSource(config.sourceLabel('alimentation_enfant')),
          text: localizedText(a.labels, lang),
        ),
      ],
    ];
  }

  static String _foodLabel(Food f, String lang) {
    final mg = f.labels['mg'] as String?;
    final fr = f.labels['fr'] as String?;
    if (lang == 'mg') return mg ?? fr ?? f.code;
    return mg == null || fr == null || mg.toLowerCase() == fr.toLowerCase() ? (fr ?? f.code) : '$fr ($mg)';
  }

  static IconData _groupIcon(int group) => switch (group) {
    1 => Icons.child_friendly,
    2 => Icons.rice_bowl,
    3 => Icons.grain,
    4 => Icons.local_drink,
    5 => Icons.set_meal,
    6 => Icons.egg,
    7 => Icons.eco,
    _ => Icons.local_florist,
  };
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.day,
    required this.isToday,
    required this.canGoForward,
    required this.canGoBack,
    required this.onMove,
  });

  final DateTime day;
  final bool isToday;
  final bool canGoForward;
  final bool canGoBack;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        IconButton(
          tooltip: l10n.previousDay,
          onPressed: canGoBack ? () => onMove(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            isToday ? '${l10n.today} · ${formatDate(day)}' : formatDate(day),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: l10n.nextDay,
          onPressed: canGoForward ? () => onMove(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(Space.touchLarge),
        backgroundColor: selected ? AppColors.accent : AppColors.surface,
        foregroundColor: selected ? Colors.white : AppColors.accent,
        alignment: Alignment.centerLeft,
      ),
      onPressed: onTap,
      icon: Icon(selected ? Icons.check_circle : icon),
      label: Text(label),
    ),
  );
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
        IconButton.outlined(
          tooltip: '${l10n.decrease} – $label',
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 40,
          child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton.outlined(
          key: ValueKey('inc-$label'),
          tooltip: '${l10n.increase} – $label',
          onPressed: value < 20 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
