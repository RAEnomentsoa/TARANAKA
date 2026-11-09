import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/danger_signs_screen.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/pregnancy_repository.dart';
import '../domain/pregnancy.dart';
import 'pregnancy_screens.dart';
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
  Future<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)>? _data;

  Future<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)> _load() async {
    final repo = pregnancyRepository(context);
    final p = await repo.current();
    if (p == null) return (null, <int, DateTime>{}, <int, DateTime>{});
    return (p, await repo.contactsDone(p.id, 'cpn'), await repo.contactsDone(p.id, 'pn'));
  }

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
    return FutureBuilder<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: ErrorView(onRetry: _reload));
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (p, ancDone, pncDone) = snap.data!;
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
        final contacts = p.delivered
            ? calc.postnatal(p.dates, pncDone, today)
            : calc.antenatal(p.dates, ancDone, today);
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
            if (next != null) ...[
              const Gap(Space.m),
              Card(
                child: ListTile(
                  key: const ValueKey('next-contact'),
                  leading: const Icon(Icons.event_available, color: AppColors.accent, size: 32),
                  title: Text(l10n.nextContact),
                  subtitle: Text(
                    '${p.delivered ? l10n.contactPnc(next.number, next.label) : l10n.contactAnc(next.number, next.label)}'
                    ' · ${formatDate(next.date)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(ContactsScreen(pregnancyId: p.id)),
                ),
              ),
            ],
            SectionTitle(p.delivered ? l10n.postpartumDangerTitle : l10n.pregnancyDangerTitle),
            DangerSignButtons(
              kind: p.delivered ? 'post_partum' : 'grossesse',
              onSignal: (code) =>
                  pregnancyRepository(context)
                      .recordDanger(p.id, code, p.delivered ? 'post_partum' : 'grossesse'),
            ),
            Text(l10n.alertDisclaimer, style: text.bodySmall),
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
