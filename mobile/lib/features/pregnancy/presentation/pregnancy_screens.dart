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
import '../domain/pregnancy.dart';
import 'pregnancy_home_screen.dart';

// ------------------------------------------------------------------ contacts

/// Antenatal and postnatal contacts, with "J'y suis allée" (spec §5).
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.pregnancyId});
  final String pregnancyId;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  Future<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)>? _data;

  Future<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)> _load() async {
    final repo = pregnancyRepository(context);
    return (
      await repo.current(),
      await repo.contactsDone(widget.pregnancyId, 'cpn'),
      await repo.contactsDone(widget.pregnancyId, 'pn'),
    );
  }

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
    return FutureBuilder<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (p, anc, pnc) = snap.data!;
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
              for (final c in calc.postnatal(p.dates, pnc, today)) tile('pn', c),
              Text(config.sourceLabel('calendrier_postnatal'), style: Theme.of(context).textTheme.bodySmall),
            ],
            SectionTitle(l10n.antenatalTitle),
            for (final c in calc.antenatal(p.dates, anc, today)) tile('cpn', c),
            Text(config.sourceLabel('calendrier_cpn'), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------- follow-up

class FollowUpScreen extends StatefulWidget {
  const FollowUpScreen({super.key, required this.pregnancyId});
  final String pregnancyId;

  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<FollowUpScreen> {
  final _weight = TextEditingController();
  final _notes = TextEditingController();
  Future<List<FollowUpEntry>>? _entries;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entries ??= pregnancyRepository(context).followUps(widget.pregnancyId);
  }

  @override
  void dispose() {
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final l10n = context.l10n;
    final weight = _weight.text.trim().isEmpty ? null : parseDecimal(_weight.text);
    if ((_weight.text.trim().isNotEmpty && (weight == null || weight < 25 || weight > 200)) ||
        (weight == null && _notes.text.trim().isEmpty)) {
      setState(() => _error = l10n.numberInvalid);
      return;
    }
    final repo = pregnancyRepository(context);
    await repo.addFollowUp(
      widget.pregnancyId,
      AppScope.read(context).services.clock.now(),
      weight,
      _notes.text,
    );
    _weight.clear();
    _notes.clear();
    setState(() {
      _error = null;
      _entries = repo.followUps(widget.pregnancyId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      title: l10n.myFollowUp,
      children: [
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.m),
        ],
        TextField(
          key: const ValueKey('followup-weight'),
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.weightKgOptional,
            prefixIcon: const Icon(Icons.monitor_weight_outlined),
          ),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('followup-notes'),
          controller: _notes,
          maxLines: 2,
          decoration: InputDecoration(labelText: l10n.notesLabel, prefixIcon: const Icon(Icons.edit_note)),
        ),
        const Gap(Space.m),
        FilledButton.icon(
          key: const ValueKey('followup-add'),
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: Text(l10n.add),
        ),
        SectionTitle(l10n.childHistory),
        FutureBuilder<List<FollowUpEntry>>(
          future: _entries,
          builder: (context, snap) {
            if (!snap.hasData) return const LoadingView();
            if (snap.data!.isEmpty) return EmptyView(icon: Icons.edit_note, message: l10n.noFollowUp);
            return Column(
              children: [
                for (final e in snap.data!)
                  Card(
                    child: ListTile(
                      title: Text(
                        [
                          formatDate(e.date),
                          if (e.weightKg != null) '${formatDecimal(e.weightKg!)} kg',
                        ].join(' · '),
                      ),
                      subtitle: e.notes.isEmpty ? null : Text(e.notes),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- movements

/// Baby movements (spec §5): the journal opens at 28 SA (config), with an
/// explanation of when they start (16 to 22 SA, config). "Le bébé bouge
/// moins" opens the red alert in one tap.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key, required this.pregnancyId});
  final String pregnancyId;

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends State<MovementsScreen> {
  Future<(Pregnancy?, Map<DateTime, int>, AlertContact)>? _data;

  Future<(Pregnancy?, Map<DateTime, int>, AlertContact)> _load() async {
    final repo = pregnancyRepository(context);
    final db = AppScope.read(context).session.active!.db;
    return (await repo.current(), await repo.movements(widget.pregnancyId), await AlertContact.load(db));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final calc = PregnancyCalculator(config);
    final today = dateOnly(scope.services.clock.now());
    return FutureBuilder<(Pregnancy?, Map<DateTime, int>, AlertContact)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (p, counts, contact) = snap.data!;
        if (p == null) return const Scaffold(body: ErrorView());
        final ga = calc.age(p.dates, today)!;
        final first = calc.firstMovementsWeeks;
        final todayCount = counts[today] ?? 0;
        final lessSign = asMapList(config.signesDanger['grossesse'])
            .where((s) => s['code'] == 'bebe_bouge_moins')
            .firstOrNull;
        return AppScreen(
          title: l10n.babyMovements,
          children: [
            NoticeBox(
              icon: Icons.info_outline,
              text: l10n.movementsExplain(first.first, first.last, calc.movementsFromWeeks),
            ),
            const Gap(Space.l),
            if (lessSign != null)
              OutlinedButton.icon(
                key: const ValueKey('movements-less'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  backgroundColor: AppColors.dangerSoft,
                  side: const BorderSide(color: AppColors.danger, width: 1.5),
                ),
                onPressed: () {
                  RedAlertScreen.open(
                    context,
                    config: config,
                    signs: [localizedText(lessSign, context.lang)],
                    contact: contact,
                  );
                  pregnancyRepository(context).recordDanger(p.id, 'bebe_bouge_moins', 'grossesse');
                },
                icon: const Icon(Icons.warning_amber_rounded),
                label: Text(l10n.movementsLess),
              ),
            if (calc.movementsLogOpen(ga)) ...[
              const Gap(Space.l),
              Text(l10n.movementsToday, style: Theme.of(context).textTheme.titleMedium),
              const Gap(Space.s),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    tooltip: l10n.decrease,
                    onPressed: todayCount > 0
                        ? () async {
                            await pregnancyRepository(context).setMovements(p.id, today, todayCount - 1);
                            setState(() {
                              _data = _load();
                            });
                          }
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      '$todayCount',
                      key: const ValueKey('movements-count'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton.filled(
                    key: const ValueKey('movements-add'),
                    tooltip: l10n.increase,
                    onPressed: () async {
                      await pregnancyRepository(context).setMovements(p.id, today, todayCount + 1);
                      setState(() {
                        _data = _load();
                      });
                    },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const Gap(Space.l),
              for (final e in counts.entries.where((e) => e.key != today))
                Text(l10n.movementsDay(formatDate(e.key), e.value)),
            ],
          ],
        );
      },
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
    final ok = diet.met(eaten);
    return AppScreen(
      title: l10n.womenDiet,
      bottomAction: Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(Radii.m)),
        child: Row(
          children: [
            Expanded(
              child: Text(l10n.womenDietScore(eaten.length), style: Theme.of(context).textTheme.titleMedium),
            ),
            StatusPill(
              icon: ok ? Icons.check_circle_outline : Icons.error_outline,
              label: ok ? l10n.diversityOk : l10n.diversityLow,
              tone: ok ? Tone.success : Tone.warning,
            ),
          ],
        ),
      ),
      children: [
        Text(l10n.womenDietHint),
        const Gap(Space.m),
        for (var i = 0; i < diet.groups.length; i++)
          CheckboxListTile(
            key: ValueKey('women-group-$i'),
            value: eaten.contains(i),
            title: Text(diet.groups[i]),
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
