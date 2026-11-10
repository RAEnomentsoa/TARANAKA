import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/alert_contact.dart';
import '../../../core/alerts/red_alert_screen.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/pregnancy_repository.dart';
import '../domain/movements.dart';
import '../domain/pregnancy.dart';
import 'pregnancy_home_screen.dart';

export 'follow_up_screen.dart' show FollowUpScreen;

// ------------------------------------------------------------------ contacts

/// Antenatal and postnatal contacts, with "J'y suis allée" (spec §5).
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.pregnancyId});
  final String pregnancyId;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  Future<PregnancyContacts>? _data;

  Future<PregnancyContacts> _load() => PregnancyContacts.load(pregnancyRepository(context));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _toggle(String type, CareContact c) async {
    final l10n = context.l10n;
    final repo = pregnancyRepository(context);
    if (c.status == ContactStatus.done) {
      final ok = await confirmAction(context, message: l10n.contactUndo, confirmLabel: l10n.confirm);
      if (!ok) return;
      await repo.unmarkContact(widget.pregnancyId, type, c.number);
    } else {
      final today = dateOnly(AppScope.read(context).services.clock.now());
      await repo.markContact(widget.pregnancyId, type, c.number, c.date.isAfter(today) ? today : c.date);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final calc = PregnancyCalculator(config);
    final today = scope.services.clock.now();
    return FutureBuilder<PregnancyContacts>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final data = snap.data!;
        final p = data.pregnancy;
        if (p == null) return const Scaffold(body: ErrorView());
        Widget tile(String type, CareContact c) {
          final title = type == 'cpn'
              ? l10n.contactAnc(c.number, c.label)
              : l10n.contactPnc(c.number, c.label);
          final pill = switch (c.status) {
            ContactStatus.done => StatusPill(
              icon: Icons.check,
              label: l10n.contactDone(formatDate(c.doneOn!)),
              tone: Tone.success,
            ),
            ContactStatus.missed => StatusPill(
              icon: Icons.error_outline,
              label: l10n.contactMissed(formatDate(c.date)),
              tone: Tone.warning,
            ),
            ContactStatus.next => StatusPill(
              icon: Icons.arrow_forward,
              label: l10n.contactNext(formatDate(c.date)),
              tone: Tone.info,
            ),
            ContactStatus.upcoming => StatusPill(
              icon: Icons.schedule,
              label: l10n.contactPlanned(formatDate(c.date)),
              tone: Tone.neutral,
            ),
          };
          return Card(
            child: CheckboxListTile(
              key: ValueKey('contact-$type-${c.number}'),
              value: c.status == ContactStatus.done,
              onChanged: (_) => _toggle(type, c),
              title: Text(title),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Align(alignment: Alignment.centerLeft, child: pill),
              ),
              secondary: Tooltip(message: l10n.contactWent, child: const Icon(Icons.how_to_reg_outlined)),
            ),
          );
        }

        return AppScreen(
          title: l10n.consultations,
          children: [
            Text(l10n.contactWent, style: Theme.of(context).textTheme.bodySmall),
            if (p.delivered) ...[
              SectionTitle(l10n.postnatalTitle),
              for (final c in data.postnatal(calc, today)) tile('pn', c),
              Text(config.sourceLabel('calendrier_postnatal'), style: Theme.of(context).textTheme.bodySmall),
            ],
            SectionTitle(l10n.antenatalTitle),
            for (final c in data.antenatal(calc, today)) tile('cpn', c),
            Text(config.sourceLabel('calendrier_cpn'), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------- movements

/// Baby movements (spec §5).
///
/// At the top, without scrolling: the alert (red, one tap opens what to do),
/// today's count with "+1 mouvement" (one tap, now), what was felt and when,
/// and "Enregistrer le mouvement". Then a short message for the term (before
/// the first movements, up to 28 SA, from 28 SA), the advice, and the whole
/// history by day and hour.
///
/// Hiccups are noted but not counted in the movements. No minimum number of
/// movements is set: each baby has its own rhythm.
///
/// Message colours: yellow for advice, blue for information, red for alerts.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key, required this.pregnancyId});
  final String pregnancyId;

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

typedef _MovementsData = (Pregnancy?, List<MovementDay>, AlertContact);

class _MovementsScreenState extends State<MovementsScreen> {
  Future<_MovementsData>? _data;
  MovementType _type = MovementType.kick;
  bool _saving = false;

  /// Null: "now" at the moment of saving.
  DateTime? _at;

  Future<_MovementsData> _load() async {
    final repo = pregnancyRepository(context);
    final db = AppScope.read(context).session.active!.db;
    final counts = await repo.movements(widget.pregnancyId);
    final events = await repo.movementEvents(widget.pregnancyId);
    return (await repo.current(), movementHistory(counts, events), await AlertContact.load(db));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() => setState(() {
    _data = _load();
  });

  String _typeLabel(MovementType t) {
    final l10n = context.l10n;
    return switch (t) {
      MovementType.kick => l10n.moveKick,
      MovementType.flutter => l10n.moveFlutter,
      MovementType.roll => l10n.moveRoll,
      MovementType.hiccup => l10n.moveHiccup,
      MovementType.stretch => l10n.moveStretch,
      MovementType.felt => l10n.moveFelt,
    };
  }

  static IconData _typeIcon(MovementType t) => switch (t) {
    MovementType.kick => Icons.sports_soccer_outlined,
    MovementType.flutter => Icons.air,
    MovementType.roll => Icons.autorenew,
    MovementType.hiccup => Icons.graphic_eq,
    MovementType.stretch => Icons.open_in_full,
    MovementType.felt => Icons.favorite_border,
  };

  String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _save(String pregnancyId, MovementType type, DateTime at, {bool quick = false}) async {
    if (_saving) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    await pregnancyRepository(context).addMovement(pregnancyId, at, type);
    if (!mounted) return;
    _saving = false;
    _reload();
    if (quick) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.movementQuickAdded(_time(at))), duration: const Duration(seconds: 2)),
        );
    }
  }

  String _stageText(PregnancyCalculator calc, GestationalAge? age) {
    final l10n = context.l10n;
    final first = calc.firstMovementsWeeks;
    if (age == null) return l10n.movementsExplain(first.first, first.last, calc.movementsFromWeeks);
    return switch (movementStage(calc, age)) {
      MovementStage.notYet => l10n.movementsStageNotYet(age.weeks, first.first, first.last),
      MovementStage.early => l10n.movementsStageEarly(age.weeks, calc.movementsFromWeeks),
      MovementStage.daily => l10n.movementsStageDaily(age.weeks),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final calc = PregnancyCalculator(config);
    final now = scope.services.clock.now();
    final today = dateOnly(now);
    final text = Theme.of(context).textTheme;
    return FutureBuilder<_MovementsData>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (p, history, contact) = snap.data!;
        if (p == null) return const Scaffold(body: ErrorView());
        final todayEntry = history.where((d) => d.date == today).firstOrNull;
        final age = p.delivered ? null : calc.age(p.dates, today);
        final lessSign = asMapList(config.signesDanger['grossesse'])
            .where((s) => s['code'] == 'bebe_bouge_moins')
            .firstOrNull;
        return AppScreen(
          title: l10n.babyMovements,
          bottomAction: FilledButton.icon(
            key: const ValueKey('movements-add'),
            onPressed: _saving ? null : () => _save(p.id, _type, _at ?? scope.services.clock.now()),
            icon: const Icon(Icons.check),
            label: Text(l10n.movementAdd),
          ),
          children: [
            // Alert (red): one tap opens what to do.
            if (lessSign != null) ...[
              NoticeBox.alert(
                key: const ValueKey('movements-less'),
                text: l10n.movementsLess,
                onTap: () {
                  RedAlertScreen.open(context, config: config, signs: [lessSign], contact: contact);
                  pregnancyRepository(context).recordDanger(p.id, 'bebe_bouge_moins', 'grossesse');
                },
              ),
              const Gap(Space.m),
            ],
            // Today's count and the one-tap "+1 mouvement".
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.m,
              runSpacing: Space.s,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${todayEntry?.count ?? 0}',
                      key: const ValueKey('movements-count'),
                      style: text.headlineMedium?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: Space.s),
                    Flexible(child: Text(l10n.movementsToday, style: text.titleSmall)),
                  ],
                ),
                // The label says "+1 mouvement" by itself (no "+1" icon before it).
                FilledButton.tonal(
                  key: const ValueKey('movements-quick'),
                  onPressed: _saving
                      ? null
                      : () => _save(p.id, MovementType.felt, scope.services.clock.now(), quick: true),
                  child: Text(l10n.movementQuickAdd),
                ),
              ],
            ),
            if ((todayEntry?.hiccups ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  l10n.movementsHiccupsToday(todayEntry!.hiccups),
                  key: const ValueKey('movements-hiccups'),
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ),
            SectionTitle(l10n.movementType),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final t in MovementType.choosable)
                  ChoiceChip(
                    key: ValueKey('movement-type-${t.code}'),
                    showCheckmark: false,
                    avatar: Icon(_type == t ? Icons.check_circle : _typeIcon(t), size: 18),
                    label: Text(_typeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const Gap(Space.m),
            DateField(
              key: const ValueKey('movement-when'),
              label: l10n.movementWhen,
              value: _at,
              withTime: true,
              first: addDays(today, -6),
              last: now,
              initial: now,
              emptyText: l10n.now,
              onChanged: (d) => setState(() => _at = d),
              onCleared: () => setState(() => _at = null),
            ),
            const Gap(Space.l),
            // Information (blue) for this term, then advice (yellow): short.
            NoticeBox.info(key: const ValueKey('movements-info'), text: _stageText(calc, age)),
            const Gap(Space.s),
            NoticeBox.tip(key: const ValueKey('movements-tip'), text: l10n.movementsTip),
            SectionTitle(l10n.movementsHistory),
            if (history.isEmpty)
              Text(l10n.movementsNoHistory, key: const ValueKey('movements-empty'))
            else
              for (final day in history) _historyDay(context, day, today),
          ],
        );
      },
    );
  }

  /// One day: its total (hiccups apart), then each movement with its hour.
  Widget _historyDay(BuildContext context, MovementDay day, DateTime today) {
    final l10n = context.l10n;
    final title = day.date == today ? '${l10n.today} · ${formatDate(day.date)}' : formatDate(day.date);
    final summary = [
      l10n.movementsDayCount(day.count),
      if (day.hiccups > 0) l10n.movementsDayHiccups(day.hiccups),
    ].join(' · ');
    return ExpansionTile(
      key: ValueKey('movement-day-${isoDate(day.date)}'),
      initiallyExpanded: day.date == today,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: Space.s),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title),
      subtitle: Text(summary),
      children: [
        if (day.events.isEmpty)
          ListTile(contentPadding: EdgeInsets.zero, title: Text(l10n.movementsDayNoHour))
        else
          for (final e in day.events)
            ListTile(
              key: ValueKey('movement-${e.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(_typeIcon(e.type), color: e.type.counts ? AppColors.accent : AppColors.textMuted),
              title: Text(_typeLabel(e.type)),
              subtitle: Text(_time(e.at)),
              trailing: IconButton(
                tooltip: l10n.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final repo = pregnancyRepository(context);
                  final ok = await confirmAction(
                    context,
                    message: l10n.deleteMovement,
                    confirmLabel: l10n.delete,
                    destructive: true,
                  );
                  if (!ok) return;
                  await repo.deleteMovement(e.id);
                  _reload();
                },
              ),
            ),
      ],
    );
  }
}

// ------------------------------------------------------------------ delivery

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.pregnancy});
  final Pregnancy pregnancy;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  late DateTime? _date = widget.pregnancy.dates.deliveredOn;
  late String _mode = widget.pregnancy.breastfeeding ?? 'exclusif';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = dateOnly(AppScope.of(context).services.clock.now());
    return AppScreen(
      title: l10n.delivery,
      bottomAction: FilledButton(
        key: const ValueKey('delivery-save'),
        onPressed: _date == null
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                await pregnancyRepository(context).recordDelivery(widget.pregnancy.id, _date!, _mode);
                messenger.showSnackBar(SnackBar(content: Text(l10n.deliverySaved)));
                navigator.pop();
              },
        child: Text(l10n.save),
      ),
      children: [
        DateField(
          key: const ValueKey('delivery-date'),
          label: l10n.deliveryDate,
          value: _date,
          first: addDays(today, -365),
          last: today,
          onChanged: (d) => setState(() => _date = d),
        ),
        SectionTitle(l10n.breastfeedingMode),
        RadioGroup<String>(
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v!),
          child: Column(
            children: [
              for (final (v, label) in [
                ('exclusif', l10n.bfExclusive),
                ('mixte', l10n.bfMixed),
                ('aucun', l10n.bfNone),
              ])
                RadioListTile<String>(value: v, title: Text(label)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- women diet

/// Optional women's dietary diversity (MDD-W, 10 groups from the config).
class WomenDietScreen extends StatefulWidget {
  const WomenDietScreen({super.key});

  @override
  State<WomenDietScreen> createState() => _WomenDietScreenState();
}

class _WomenDietScreenState extends State<WomenDietScreen> {
  Set<int>? _eaten;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_eaten != null) return;
    pregnancyRepository(context).dietOn(AppScope.read(context).services.clock.now()).then((g) {
      if (mounted) setState(() => _eaten = g);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final diet = WomenDiet(config);
    final eaten = _eaten;
    if (eaten == null) return const Scaffold(body: LoadingView());
    // Each food name is shown only once (see WomenDiet.shown).
    final shown = diet.shown(context.lang);
    final ok = diet.metShown(eaten, context.lang);
    final count = diet.eatenShown(eaten, context.lang).length;
    return AppScreen(
      title: l10n.womenDiet,
      bottomAction: Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(Radii.m)),
        child: LabelWithPill(
          label: Text(l10n.womenDietScore(count), style: Theme.of(context).textTheme.titleMedium),
          pill: StatusPill(
            icon: ok ? Icons.check_circle_outline : Icons.error_outline,
            label: ok ? l10n.diversityOk : l10n.diversityLow,
            tone: ok ? Tone.success : Tone.warning,
          ),
        ),
      ),
      children: [
        Text(l10n.womenDietHint),
        const Gap(Space.m),
        for (final (i, label) in shown)
          CheckboxListTile(
            key: ValueKey('women-group-$i'),
            value: eaten.contains(i),
            title: Text(label),
            onChanged: (v) async {
              final next = {...eaten};
              v == true ? next.add(i) : next.remove(i);
              setState(() => _eaten = next);
              await pregnancyRepository(context).setDiet(scope.services.clock.now(), next);
            },
          ),
        const Gap(Space.m),
        Text(config.sourceLabel('alimentation_femme'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
