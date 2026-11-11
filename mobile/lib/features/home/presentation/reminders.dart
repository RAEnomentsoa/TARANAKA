import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/util/clock.dart';
import '../../child/application/vaccine_reminders_sync.dart';
import '../../child/data/child_repository.dart';
import '../../child/domain/vaccines.dart';
import '../../pregnancy/data/pregnancy_repository.dart';
import '../../pregnancy/domain/pregnancy.dart';

/// One reminder, with an id that does not depend on the language: the bell
/// counts the ones not seen yet.
class ReminderItem {
  const ReminderItem(this.id, this.text);
  final String id;
  final String text;
}

/// Bumped when coming back to the home (a module may have changed the
/// reminders): the bell and the home list load them again.
final remindersRevision = ValueNotifier<int>(0);

/// The reminders of the active profile (spec §5, §6), computed on the phone.
/// [syncPhone] also sets the vaccine reminders of the phone.
Future<List<ReminderItem>> loadReminders(BuildContext context, {bool syncPhone = false}) async {
  final l10n = context.l10n;
  final scope = AppScope.read(context);
  // Locked or switched while a module was open: nothing to show.
  final active = scope.session.active;
  if (active == null) return const [];
  final db = active.db;
  final config = scope.services.config.current;
  final today = dateOnly(scope.services.clock.now());
  final out = <ReminderItem>[];
  final profileId = active.info.id;
  if (syncPhone) {
    unawaited(
      syncVaccineReminders(
        db: db,
        config: config,
        l10n: l10n,
        profileId: profileId,
        now: scope.services.clock.now(),
      ).catchError((Object _) {}),
    );
  }
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
      out.add(
        ReminderItem(
          'contact:${pregnancy.id}:${isoDate(next.date)}',
          l10n.reminderNextAnc(formatDate(next.date)),
        ),
      );
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
    if (late > 0) out.add(ReminderItem('vaccines:${c.id}:$late', l10n.reminderVaccines(c.name, late)));
  }
  return out;
}
