import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../../child/application/vaccine_reminders_sync.dart';
import '../../child/data/child_repository.dart';
import '../../child/domain/vaccines.dart';
import '../../pregnancy/data/pregnancy_repository.dart';
import '../../pregnancy/domain/pregnancy.dart';

/// Offline reminders shown on the personal home (spec §5, §6): the next
/// antenatal or postnatal contact within 7 days, and late vaccines. Computed
/// on the phone, no network. Opening the home also sets the vaccine
/// reminders of the phone (notifications whose lock-screen text says
/// nothing about health).
class PersonalReminders extends StatefulWidget {
  const PersonalReminders({super.key});

  @override
  State<PersonalReminders> createState() => _PersonalRemindersState();
}

class _PersonalRemindersState extends State<PersonalReminders> {
  Future<List<String>>? _items;

  Future<List<String>> _load(BuildContext context) async {
    final l10n = context.l10n;
    final scope = AppScope.read(context);
    final db = scope.session.active!.db;
    final config = scope.services.config.current;
    final today = dateOnly(scope.services.clock.now());
    final out = <String>[];
    final profileId = scope.session.active!.info.id;
    unawaited(
      syncVaccineReminders(
        db: db,
        config: config,
        l10n: l10n,
        profileId: profileId,
        now: scope.services.clock.now(),
      ).catchError((Object _) {}),
    );
    final pregnancy = await PregnancyRepository(db).current();
    if (pregnancy != null) {
      final calc = PregnancyCalculator(config);
      final repo = PregnancyRepository(db);
      final contacts = pregnancy.delivered
          ? calc.postnatal(
              pregnancy.dates,
              await repo.contactsDone(pregnancy.id, 'pn'),
              today,
              moved: await repo.contactsMoved(pregnancy.id, 'pn'),
            )
          : calc.antenatal(
              pregnancy.dates,
              await repo.contactsDone(pregnancy.id, 'cpn'),
              today,
              moved: await repo.contactsMoved(pregnancy.id, 'cpn'),
            );
      final next = contacts.where((c) => c.status == ContactStatus.next).firstOrNull;
      if (next != null && daysBetween(today, next.date) <= 7) {
        out.add(l10n.reminderNextAnc(formatDate(next.date)));
      }
    }
    final children = ChildRepository(db);
    for (final c in await children.children()) {
      final late = VaccineSchedule.build(
        config,
        birthDate: c.birthDate,
        done: await children.vaccinesDone(c.id),
        today: today,
      ).where((d) => d.status == DoseStatus.late).length;
      if (late > 0) out.add(l10n.reminderVaccines(c.name, late));
    }
    return out;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items = _load(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _items,
      builder: (context, snap) {
        final items = snap.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Space.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.remindersTitle, style: Theme.of(context).textTheme.titleSmall),
              const Gap(Space.s),
              for (final i in items) ...[
                NoticeBox(icon: Icons.notifications_none, text: i),
                const Gap(Space.s),
              ],
            ],
          ),
        );
      },
    );
  }
}
