import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/danger_signs_screen.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/pregnancy_repository.dart';
import '../domain/pregnancy.dart';
import '../domain/pregnancy_weeks.dart';
import 'pregnancy_screens.dart';
import 'pregnancy_week_screen.dart';
import 'pregnancy_setup_screen.dart';

PregnancyRepository pregnancyRepository(BuildContext context) {
  final scope = AppScope.read(context);
  return PregnancyRepository(scope.session.active!.db, clock: scope.services.clock);
}

/// "Ma grossesse et post-partum" (spec §5).
class PregnancyHomeScreen extends StatefulWidget {
  const PregnancyHomeScreen({super.key});

  @override
  State<PregnancyHomeScreen> createState() => _PregnancyHomeScreenState();
}

class _PregnancyHomeScreenState extends State<PregnancyHomeScreen> {
  Future<PregnancyContacts>? _data;

  Future<PregnancyContacts> _load() => PregnancyContacts.load(pregnancyRepository(context));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() {
    if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
    setState(() {
      _data = _load();
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final today = dateOnly(scope.services.clock.now());
    final calc = PregnancyCalculator(config);
    return FutureBuilder<PregnancyContacts>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: ErrorView(onRetry: _reload));
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final data = snap.data!;
        final p = data.pregnancy;
        if (p == null) {
          return PregnancySetupForm(
            onSave: (dates) async {
              await pregnancyRepository(context).start(dates, calc);
              _reload();
            },
          );
        }
        final ga = calc.age(p.dates, today)!;
        final due = calc.dueDate(p.dates);
        final contacts = p.delivered ? data.postnatal(calc, today) : data.antenatal(calc, today);
        final next = contacts.where((c) => c.status == ContactStatus.next).firstOrNull;
        final text = Theme.of(context).textTheme;

        return AppScreen(
          title: l10n.tilePregnancy,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: p.delivered
                    ? Text(
                        l10n.postpartumLabel(
                          formatDate(p.dates.deliveredOn!),
                          daysBetween(p.dates.deliveredOn!, today),
                        ),
                        style: text.titleLarge,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.gaLabel, style: text.labelLarge?.copyWith(color: AppColors.textMuted)),
                          Text(
                            l10n.gaValue(ga.weeks, ga.days),
                            key: const ValueKey('ga-value'),
                            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Gap(Space.s),
                          Wrap(
                            spacing: Space.s,
                            runSpacing: Space.s,
                            children: [
                              StatusPill(
                                icon: Icons.timelapse,
                                label: l10n.trimesterLabel(calc.trimester(ga)),
                                tone: Tone.info,
                              ),
                              if (due != null)
                                StatusPill(
                                  key: const ValueKey('due-date'),
                                  icon: Icons.event,
                                  label: l10n.dueDateLabel(formatDate(due)),
                                  tone: Tone.neutral,
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
            if (!p.delivered && due != null && today.isAfter(due)) ...[
              const Gap(Space.m),
              NoticeBox(
                key: const ValueKey('due-passed'),
                icon: Icons.event_busy_outlined,
                tone: Tone.warning,
                text: l10n.duePassed,
              ),
            ],
            if (!p.delivered) ...[
              const Gap(Space.m),
              _WeekCard(
                weeks: ga.weeks,
                onTap: () => _open(PregnancyWeekScreen(currentWeek: ga.weeks)),
              ),
            ],
            if (next != null) ...[
              const Gap(Space.m),
              _NextContactCard(
                contact: next,
                pregnancy: p,
                calc: calc,
                today: today,
                onOpen: () => _open(ContactsScreen(pregnancyId: p.id)),
                onChanged: _reload,
              ),
            ],
            const Gap(Space.l),
            DangerSignsPanel(
              kind: p.delivered ? 'post_partum' : 'grossesse',
              title: p.delivered ? l10n.postpartumDangerHeader : l10n.pregnancyDangerHeader,
              onSignal: (code) =>
                  pregnancyRepository(context)
                      .recordDanger(p.id, code, p.delivered ? 'post_partum' : 'grossesse'),
            ),
            const Gap(Space.l),
            BigTile(
              key: const ValueKey('pregnancy-contacts'),
              icon: Icons.event_note,
              title: l10n.consultations,
              onTap: () => _open(ContactsScreen(pregnancyId: p.id)),
            ),
            const Gap(Space.m),
            BigTile(
              key: const ValueKey('pregnancy-followup'),
              icon: Icons.monitor_weight_outlined,
              title: l10n.myFollowUp,
              onTap: () => _open(FollowUpScreen(pregnancyId: p.id)),
            ),
            const Gap(Space.m),
            // "Mouvements du bébé", right under "Mon suivi": always shown,
            // whatever the SA (even before 28 SA) and after the delivery.
            BigTile(
              key: const ValueKey('pregnancy-movements'),
              icon: Icons.favorite_border,
              title: l10n.babyMovements,
              onTap: () => _open(MovementsScreen(pregnancyId: p.id)),
            ),
            const Gap(Space.m),
            BigTile(
              key: const ValueKey('pregnancy-diet'),
              icon: Icons.restaurant_outlined,
              title: l10n.womenDiet,
              onTap: () => _open(const WomenDietScreen()),
            ),
            const Gap(Space.m),
            BigTile(
              key: const ValueKey('pregnancy-delivery'),
              icon: Icons.child_friendly,
              title: l10n.delivery,
              onTap: () => _open(DeliveryScreen(pregnancy: p)),
            ),
            const Gap(Space.l),
            Wrap(
              spacing: Space.s,
              children: [
                TextButton.icon(
                  onPressed: () => _open(
                    PregnancySetupForm(
                      title: l10n.changeDates,
                      initial: p.dates,
                      onSave: (dates) async {
                        final navigator = Navigator.of(context);
                        await pregnancyRepository(context).updateDates(p.id, dates, calc);
                        navigator.pop();
                      },
                    ),
                  ),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: Text(l10n.changeDates),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await confirmAction(
                      context,
                      message: l10n.endPregnancyConfirm,
                      confirmLabel: l10n.confirm,
                    );
                    if (!ok || !context.mounted) return;
                    await pregnancyRepository(context).close(p.id);
                    _reload();
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(l10n.endPregnancy),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// "Ma grossesse semaine par semaine": the baby and the body at today's SA.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.weeks, required this.onTap});

  final int weeks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final info = pregnancyWeekInfo(weeks);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('pregnancy-week'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.child_care, color: AppColors.accent, size: 28),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(l10n.pregnancyWeekTitle, style: text.titleMedium)),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const Gap(Space.s),
              Text(l10n.pregnancyWeekIntro(weeks), key: const ValueKey('pregnancy-week-intro')),
              const Gap(Space.s),
              Text(
                info.babyIn(context.lang),
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const Gap(Space.xs),
              Text(l10n.weekSee, style: text.labelLarge?.copyWith(color: AppColors.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The next contact: its date, the SA (or day after birth) on that very date,
/// how long until then, and "Modifier la date".
class _NextContactCard extends StatelessWidget {
  const _NextContactCard({
    required this.contact,
    required this.pregnancy,
    required this.calc,
    required this.today,
    required this.onOpen,
    required this.onChanged,
  });

  final CareContact contact;
  final Pregnancy pregnancy;
  final PregnancyCalculator calc;
  final DateTime today;
  final VoidCallback onOpen;
  final VoidCallback onChanged;

  String get _type => pregnancy.delivered ? 'pn' : 'cpn';

  Future<void> _changeDate(BuildContext context) async {
    final l10n = context.l10n;
    final due = calc.dueDate(pregnancy.dates);
    final last = pregnancy.delivered
        ? addDays(pregnancy.dates.deliveredOn!, 90)
        : addDays(due ?? addDays(today, calc.naegeleDays), 21);
    final picked = await showDateWheel(
      context,
      title: l10n.contactDateTitle,
      initial: contact.date.isBefore(today) ? today : contact.date,
      first: today,
      last: last.isBefore(today) ? today : last,
    );
    if (picked == null || !context.mounted) return;
    await pregnancyRepository(context).moveContact(pregnancy.id, _type, contact.number, picked);
    onChanged();
  }

  Future<void> _reset(BuildContext context) async {
    await pregnancyRepository(context).moveContact(pregnancy.id, _type, contact.number, null);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final date = formatDate(contact.date);
    // SA reckoned on the date of the contact itself, never today's SA.
    final ageThen = pregnancy.delivered ? null : calc.age(pregnancy.dates, contact.date);
    final inDays = daysBetween(today, contact.date);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_available, color: AppColors.accent, size: 32),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    pregnancy.delivered ? l10n.nextPncTitle(date) : l10n.nextAncTitle(date),
                    key: const ValueKey('next-contact'),
                    style: text.titleMedium,
                  ),
                ),
              ],
            ),
            const Gap(Space.s),
            Text(
              ageThen == null
                  ? l10n.contactPnc(contact.number, contact.label)
                  : l10n.nextAncDetail(contact.number, ageThen.weeks, ageThen.days),
              key: const ValueKey('next-contact-detail'),
            ),
            Text(l10n.contactInDays(inDays), style: text.bodySmall),
            if (contact.moved)
              Text(
                l10n.contactMovedFrom(formatDate(contact.plannedDate)),
                key: const ValueKey('next-contact-moved'),
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            const Gap(Space.xs),
            Wrap(
              spacing: Space.s,
              children: [
                TextButton.icon(
                  key: const ValueKey('next-contact-edit'),
                  onPressed: () => _changeDate(context),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: Text(l10n.changeContactDate),
                ),
                if (contact.moved)
                  TextButton.icon(
                    key: const ValueKey('next-contact-reset'),
                    onPressed: () => _reset(context),
                    icon: const Icon(Icons.restore),
                    label: Text(l10n.contactDateReset),
                  ),
                TextButton.icon(
                  key: const ValueKey('next-contact-all'),
                  onPressed: onOpen,
                  icon: const Icon(Icons.event_note),
                  label: Text(l10n.consultations),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
