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
import '../../../core/widgets/time_wheel.dart';
import '../../agent/domain/screening.dart';
import '../data/child_repository.dart';
import '../domain/feeding.dart';
import 'my_children_screen.dart';

/// Feeding by age (spec §6): exclusive breastfeeding for 0–5 months (only
/// breast milk, at the breast or expressed), then from 6 months breastfeeding
/// goes on with other foods: food diary by pictograms for 6–23 months, with
/// the WHO/UNICEF indicators and advice from the validated library. Feeds
/// (time, duration, expressed milk), a weekly summary and practical tips.
/// Saved on every tap.
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
  List<Food> _custom = const [];
  List<BreastFeed> _feeds = const [];
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
    final custom = await repo.customFoods();
    final feeds = await repo.feeds(widget.childId, _day);
    if (!mounted) return;
    setState(() {
      _custom = custom;
      _feeds = feeds;
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

  /// Notes a feed (sheet), then reloads the day. From 6 months, a feed also
  /// ticks breast milk in the food diary.
  Future<void> _addFeed(FeedingRules? rules) async {
    final today = dateOnly(AppScope.read(context).services.clock.now());
    final now = AppScope.read(context).services.clock.now();
    final feed = await showModalBottomSheet<_NewFeed>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FeedSheet(
        initial: _day == today ? TimeOfDay.fromDateTime(now) : const TimeOfDay(hour: 12, minute: 0),
      ),
    );
    if (feed == null || !mounted) return;
    final repo = childRepository(context);
    final at = DateTime(_day.year, _day.month, _day.day, feed.time.hour, feed.time.minute);
    await repo.addFeed(widget.childId, at, feed.type, minutes: feed.minutes, millilitres: feed.millilitres);
    final breastMilk = rules?.foods.where((f) => f.group == rules.breastMilkGroup).firstOrNull;
    if (rules != null && breastMilk != null && !_current.foods.contains(breastMilk.code)) {
      final log = _current;
      await _save(
        FeedingLog(
          date: _day,
          breastfeeding: 'mixte',
          foods: {...log.foods, breastMilk.code},
          meals: log.meals,
          milkFeeds: log.milkFeeds,
        ),
      );
    }
    final feeds = await repo.feeds(widget.childId, _day);
    if (mounted) setState(() => _feeds = feeds);
  }

  Future<void> _deleteFeed(BreastFeed feed) async {
    final l10n = context.l10n;
    final repo = childRepository(context);
    final ok = await confirmAction(
      context,
      message: l10n.feedDelete,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!ok) return;
    await repo.deleteFeed(feed.id);
    final feeds = await repo.feeds(widget.childId, _day);
    if (mounted) setState(() => _feeds = feeds);
  }

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
    final rules = FeedingRules(config, custom: _custom);
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
          ..._breastfeeding(context, child, today)
        else if (diaryAge) ...[
          // From 6 months: breastfeeding goes on, with other foods.
          NoticeBox(
            key: const ValueKey('after-6-months'),
            icon: Icons.restaurant,
            text: l10n.breastfeedingAfter6,
          ),
          const Gap(Space.l),
          _FeedsCard(feeds: _feeds, legacyCount: null, onAdd: () => _addFeed(rules), onDelete: _deleteFeed),
          const Gap(Space.l),
          ..._diary(context, rules, months, config),
          const Gap(Space.l),
          const _BreastfeedingTips(),
        ] else
          NoticeBox(icon: Icons.info_outline, text: l10n.feedingNotInRange),
        if (_log != null) ...[
          const Gap(Space.l),
          const Align(alignment: Alignment.centerLeft, child: SyncStatusPill(SyncStatus.saved)),
        ],
      ],
    );
  }

  List<Widget> _breastfeeding(BuildContext context, MyChild child, DateTime today) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final log = _current;
    final exclusive = _log?.breastfeeding == 'exclusif';
    final notExclusive = _log != null && _log!.breastfeeding != 'exclusif';
    FeedingLog answer(String type, Set<String> others) => FeedingLog(
      date: _day,
      breastfeeding: type,
      foods: const {},
      meals: 0,
      milkFeeds: 0,
      breastFeeds: log.breastFeeds,
      others: others,
    );
    final labels = l10n.otherIntakeLabels.split('|');
    final end = _day.isAfter(today) ? today : _day;
    return [
      Text(l10n.exclusiveQuestion, key: const ValueKey('exclusive-question'), style: text.titleMedium),
      const Gap(Space.m),
      _ChoiceButton(
        key: const ValueKey('exclusive-yes'),
        selected: exclusive,
        icon: Icons.check_circle_outline,
        label: l10n.exclusiveYes,
        onTap: () => _save(answer('exclusif', const {})),
      ),
      const Gap(Space.s),
      _ChoiceButton(
        key: const ValueKey('exclusive-no'),
        selected: notExclusive,
        icon: Icons.cancel_outlined,
        label: l10n.exclusiveNo,
        onTap: () => _save(answer('mixte', log.others)),
      ),
      if (notExclusive) ...[
        const Gap(Space.l),
        Text(l10n.othersQuestion, key: const ValueKey('others-question'), style: text.titleSmall),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (i, code) in otherIntakes.indexed)
              FilterChip(
                key: ValueKey('other-$code'),
                label: Text(labels[i]),
                selected: log.others.contains(code),
                onSelected: (on) =>
                    _save(answer('mixte', on ? {...log.others, code} : ({...log.others}..remove(code)))),
              ),
          ],
        ),
        const Gap(Space.m),
        NoticeBox(icon: Icons.info_outline, tone: Tone.caution, text: l10n.exclusiveAdvice),
      ],
      const Gap(Space.l),
      _FeedsCard(
        feeds: _feeds,
        legacyCount: _feeds.isEmpty ? log.breastFeeds : null,
        onAdd: () => _addFeed(null),
        onDelete: _deleteFeed,
      ),
      const Gap(Space.l),
      _WeekSummary(
        days: breastfeedingWeek(
          answers: {for (final l in _week) dateOnly(l.date): l.breastfeeding},
          end: end,
          birth: child.birthDate,
        ),
        selected: _day,
        onTap: (d) => _move(daysBetween(_day, d)),
      ),
      const Gap(Space.l),
      const _BreastfeedingTips(),
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

    final text = Theme.of(context).textTheme;
    return [
      Text(l10n.tapFoods, style: text.titleMedium),
      // One block per food group: each food appears once, under its group.
      for (final (group, foods) in rules.foodsByGroup()) ...[
        const Gap(Space.m),
        Semantics(
          header: true,
          child: Row(
            children: [
              Icon(_groupIcon(group.number), size: 20, color: AppColors.accent),
              const SizedBox(width: Space.s),
              Expanded(child: Text(localizedText(group.labels, lang), style: text.titleSmall)),
              if (indicators.groups.contains(group.number))
                Icon(Icons.check_circle, size: 20, color: AppColors.success, semanticLabel: l10n.yes),
            ],
          ),
        ),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final f in foods)
              if (!f.hidden || log.foods.contains(f.code))
                GestureDetector(
                  // A food added by the user can be removed from the list.
                  onLongPress: f.custom ? () => _removeFood(f) : null,
                  child: FilterChip(
                    key: ValueKey('food-${f.code}'),
                    label: Text(_foodLabel(f, lang)),
                    avatar: f.custom ? const Icon(Icons.edit_note, size: 18) : null,
                    selected: log.foods.contains(f.code),
                    onSelected: (v) {
                      final foods = {...log.foods};
                      v ? foods.add(f.code) : foods.remove(f.code);
                      _save(next(foods: foods));
                    },
                  ),
                ),
            // Free entry: a food or a variety missing from the list.
            if (group.number != rules.breastMilkGroup)
              ActionChip(
                key: ValueKey('food-add-${group.number}'),
                avatar: const Icon(Icons.add, size: 18),
                label: Text(l10n.foodAdd),
                onPressed: () =>
                    _addFood(rules, group, lang, (code) => _save(next(foods: {...log.foods, code}))),
              ),
          ],
        ),
      ],
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
      // Diversity is pinned at the bottom of the screen; here, the other two
      // indicators.
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (indicators.mealsRequired != null) ...[
                LabelWithPill(
                  label: Text(l10n.mealsScore(log.meals, indicators.mealsRequired!)),
                  pill: StatusPill(
                    icon: indicators.mealsMet ? Icons.check : Icons.close,
                    label: indicators.mealsMet ? l10n.yes : l10n.no,
                    tone: indicators.mealsMet ? Tone.success : Tone.warning,
                  ),
                ),
                const Gap(Space.s),
              ],
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

  /// Asks the name of a new food of [group], keeps it for the profile and
  /// ticks it for the day ([onAdded]).
  Future<void> _addFood(
    FeedingRules rules,
    FoodGroup group,
    String lang,
    ValueChanged<String> onAdded,
  ) async {
    final repo = childRepository(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FoodNameDialog(
        title: context.l10n.foodAddTitle(localizedText(group.labels, lang)),
        exists: (n) => rules.hasFood(group.number, n),
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final food = await repo.addCustomFood(group.number, name);
    if (!mounted) return;
    setState(() => _custom = [..._custom, food]);
    onAdded(food.code);
  }

  Future<void> _removeFood(Food food) async {
    final l10n = context.l10n;
    final repo = childRepository(context);
    final ok = await confirmAction(
      context,
      message: l10n.foodRemove(food.name),
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!ok) return;
    await repo.removeCustomFood(food.code);
    final custom = await repo.customFoods();
    if (mounted) setState(() => _custom = custom);
  }

  /// The food name in the chosen language only.
  static String _foodLabel(Food f, String lang) {
    final label = localizedText(f.labels, lang);
    return label.isEmpty ? f.code : label;
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
  const _Counter({
    required this.label,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.max = 20,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int step;
  final int max;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
        IconButton.outlined(
          tooltip: '${l10n.decrease} – $label',
          onPressed: value > 0 ? () => onChanged((value - step).clamp(0, max)) : null,
          icon: const Icon(Icons.remove),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton.outlined(
          key: ValueKey('inc-$label'),
          tooltip: '${l10n.increase} – $label',
          onPressed: value < max ? () => onChanged((value + step).clamp(0, max)) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Name of a food typed by the user; refuses a food already in the group.
class _FoodNameDialog extends StatefulWidget {
  const _FoodNameDialog({required this.title, required this.exists});

  final String title;
  final bool Function(String name) exists;

  @override
  State<_FoodNameDialog> createState() => _FoodNameDialogState();
}

class _FoodNameDialogState extends State<_FoodNameDialog> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.fieldRequired);
    } else if (widget.exists(name)) {
      setState(() => _error = l10n.foodExists);
    } else {
      Navigator.of(context).pop(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('food-name'),
              controller: _name,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: l10n.foodNameLabel, errorText: _error),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            Text(l10n.foodCustomHint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(key: const ValueKey('food-name-save'), onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}

/// A feed being noted in the sheet.
class _NewFeed {
  const _NewFeed(this.type, this.time, this.minutes, this.millilitres);
  final String type;
  final TimeOfDay time;
  final int? minutes;
  final int? millilitres;
}

String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "Tétées et lait exprimé": the feeds of the day, their totals, "Noter une
/// tétée". Tapping a feed deletes it (after confirmation).
class _FeedsCard extends StatelessWidget {
  const _FeedsCard({
    required this.feeds,
    required this.legacyCount,
    required this.onAdd,
    required this.onDelete,
  });

  final List<BreastFeed> feeds;

  /// Feeds counted on an older version, for a day without feed log.
  final int? legacyCount;
  final VoidCallback onAdd;
  final ValueChanged<BreastFeed> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final totals = FeedTotals.of(feeds);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, color: AppColors.accent),
                const SizedBox(width: Space.s),
                Expanded(child: Text(l10n.feedsTitle, style: text.titleMedium)),
              ],
            ),
            const Gap(Space.s),
            if (feeds.isEmpty)
              Text(
                (legacyCount ?? 0) > 0 ? l10n.breastFeedsLegacy(legacyCount!) : l10n.feedsNone,
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              )
            else ...[
              Text(
                l10n.feedsTotal(totals.feeds, totals.minutes, totals.millilitres),
                key: const ValueKey('feeds-total'),
                style: text.bodyLarge,
              ),
              const Gap(Space.xs),
              for (final f in feeds)
                ListTile(
                  key: ValueKey('feed-${f.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    f.isExpressed ? Icons.local_drink_outlined : Icons.child_care,
                    color: AppColors.accent,
                  ),
                  title: Text(
                    [
                      _hhmm(TimeOfDay.fromDateTime(f.at)),
                      f.isExpressed ? l10n.feedTypeExpressed : l10n.feedTypeBreast,
                      if ((f.minutes ?? 0) > 0) l10n.minutesShort(f.minutes!),
                      if ((f.millilitres ?? 0) > 0) l10n.mlShort(f.millilitres!),
                    ].join(' · '),
                  ),
                  trailing: Icon(Icons.delete_outline, semanticLabel: l10n.delete),
                  onTap: () => onDelete(f),
                ),
            ],
            const Gap(Space.s),
            OutlinedButton.icon(
              key: const ValueKey('feed-add'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(l10n.feedAdd),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet to note a feed: at the breast (duration) or expressed breast milk
/// (quantity), and its time. "Enregistrer" stays visible under the fields.
class _FeedSheet extends StatefulWidget {
  const _FeedSheet({required this.initial});
  final TimeOfDay initial;

  @override
  State<_FeedSheet> createState() => _FeedSheetState();
}

class _FeedSheetState extends State<_FeedSheet> {
  String _type = BreastFeed.atBreast;
  late TimeOfDay _time = widget.initial;
  int _minutes = 15;
  int _ml = 60;

  Future<void> _pickTime() async {
    final picked = await showTimeWheel(context, title: context.l10n.feedTime, initial: _time);
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final expressed = _type == BreastFeed.expressed;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                  Text(l10n.feedAdd, style: text.titleMedium),
                  const Gap(Space.m),
                  Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('feed-type-sein'),
                        avatar: const Icon(Icons.child_care, size: 18),
                        label: Text(l10n.feedTypeBreast),
                        selected: !expressed,
                        onSelected: (_) => setState(() => _type = BreastFeed.atBreast),
                      ),
                      ChoiceChip(
                        key: const ValueKey('feed-type-exprime'),
                        avatar: const Icon(Icons.local_drink_outlined, size: 18),
                        label: Text(l10n.feedTypeExpressed),
                        selected: expressed,
                        onSelected: (_) => setState(() => _type = BreastFeed.expressed),
                      ),
                    ],
                  ),
                  if (expressed) ...[const Gap(Space.s), Text(l10n.feedExpressedHint, style: text.bodySmall)],
                  const Gap(Space.m),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.feedTime, style: text.bodyLarge)),
                      OutlinedButton.icon(
                        key: const ValueKey('feed-time'),
                        onPressed: _pickTime,
                        icon: const Icon(Icons.access_time),
                        label: Text(_hhmm(_time)),
                      ),
                    ],
                  ),
                  const Gap(Space.s),
                  if (expressed)
                    _Counter(
                      label: l10n.feedQuantity,
                      value: _ml,
                      step: 10,
                      max: 300,
                      onChanged: (v) => setState(() => _ml = v),
                    )
                  else
                    _Counter(
                      label: l10n.feedDuration,
                      value: _minutes,
                      step: 5,
                      max: 90,
                      onChanged: (v) => setState(() => _minutes = v),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
              child: FilledButton(
                key: const ValueKey('feed-save'),
                onPressed: () => Navigator.of(context).pop(
                  _NewFeed(
                    _type,
                    _time,
                    expressed ? null : (_minutes > 0 ? _minutes : null),
                    expressed ? (_ml > 0 ? _ml : null) : null,
                  ),
                ),
                child: Text(l10n.save),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The last 7 days: exclusive, mixed or not noted, each with its own icon
/// and colour (never colour alone), and the count of each.
class _WeekSummary extends StatelessWidget {
  const _WeekSummary({required this.days, required this.selected, required this.onTap});

  final List<(DateTime, BreastfeedingDay)> days;
  final DateTime selected;
  final ValueChanged<DateTime> onTap;

  static ({IconData icon, Color fg, Color bg}) _style(BreastfeedingDay d) => switch (d) {
    BreastfeedingDay.exclusive => (
      icon: Icons.check_circle,
      fg: AppColors.success,
      bg: AppColors.successSoft,
    ),
    BreastfeedingDay.mixed => (
      icon: Icons.change_circle_outlined,
      fg: AppColors.warning,
      bg: AppColors.warningSoft,
    ),
    BreastfeedingDay.notNoted => (
      icon: Icons.remove_circle_outline,
      fg: AppColors.neutral,
      bg: AppColors.neutralSoft,
    ),
  };

  static String _label(AppLocalizations l10n, BreastfeedingDay d) => switch (d) {
    BreastfeedingDay.exclusive => l10n.bfDayExclusive,
    BreastfeedingDay.mixed => l10n.bfDayMixed,
    BreastfeedingDay.notNoted => l10n.bfDayNotNoted,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final weekdays = l10n.weekdayShort.split('|');
    int count(BreastfeedingDay d) => days.where((e) => e.$2 == d).length;
    return Card(
      key: const ValueKey('bf-week'),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_outlined, color: AppColors.accent),
                const SizedBox(width: Space.s),
                Expanded(child: Text(l10n.bfWeekTitle, style: text.titleMedium)),
              ],
            ),
            const Gap(Space.m),
            Row(
              children: [
                for (final (d, status) in days)
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: '${formatDate(d)}, ${_label(l10n, status)}',
                      excludeSemantics: true,
                      child: InkWell(
                        key: ValueKey('bf-day-${isoDate(d)}'),
                        borderRadius: BorderRadius.circular(Radii.s),
                        onTap: () => onTap(d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: 1),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              children: [
                                Text(
                                  weekdays[d.weekday - 1],
                                  style: text.labelSmall?.copyWith(color: AppColors.textMuted),
                                ),
                                const Gap(Space.xs),
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: _style(status).bg,
                                    shape: BoxShape.circle,
                                    border: d == selected
                                        ? Border.all(color: AppColors.text, width: 2)
                                        : null,
                                  ),
                                  child: Icon(_style(status).icon, color: _style(status).fg, size: 22),
                                ),
                                const Gap(Space.xs),
                                Text('${d.day}', style: text.labelMedium),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const Gap(Space.m),
            for (final status in BreastfeedingDay.values)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(
                  children: [
                    Icon(_style(status).icon, color: _style(status).fg, size: 20),
                    const SizedBox(width: Space.s),
                    Expanded(child: Text(_label(l10n, status), style: text.bodyMedium)),
                    Text(
                      l10n.daysCount(count(status)),
                      key: ValueKey('bf-count-${status.name}'),
                      style: text.titleSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Short practical tips, folded: good position, common difficulties, signs
/// that the baby gets enough milk.
class _BreastfeedingTips extends StatelessWidget {
  const _BreastfeedingTips();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final tips = [
      ('position', Icons.accessibility_new, l10n.tipPositionTitle, l10n.tipPosition),
      ('difficulties', Icons.healing_outlined, l10n.tipDifficultiesTitle, l10n.tipDifficulties),
      ('enough', Icons.thumb_up_alt_outlined, l10n.tipEnoughTitle, l10n.tipEnough),
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: AppColors.accent),
                const SizedBox(width: Space.s),
                Expanded(child: Text(l10n.tipsTitle, style: text.titleMedium)),
              ],
            ),
          ),
          for (final (code, icon, title, body) in tips)
            ExpansionTile(
              key: ValueKey('tip-$code'),
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(icon, color: AppColors.accent),
              title: Text(title, style: text.titleSmall),
              childrenPadding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in body.split('|'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.s),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Icon(Icons.circle, size: 6, color: AppColors.textMuted),
                        ),
                        const SizedBox(width: Space.s),
                        Expanded(child: Text(line, style: text.bodyMedium)),
                      ],
                    ),
                  ),
              ],
            ),
          const Gap(Space.s),
        ],
      ),
    );
  }
}
