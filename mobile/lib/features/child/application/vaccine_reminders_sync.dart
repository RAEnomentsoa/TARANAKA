import '../../../core/config/clinical_config.dart';
import '../../../core/db/app_database.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/platform/local_reminders.dart';
import '../data/child_repository.dart';
import '../domain/vaccines.dart';

/// Group of the vaccine reminders of a profile.
String vaccineReminderGroup(String profileId) => 'vaccins-$profileId';

/// Sets the vaccine reminders of every child of the open profile: 7 days
/// before, the day before, and when late (see [vaccineReminders]). Called
/// when the home opens and after each change of a vaccine.
Future<void> syncVaccineReminders({
  required AppDatabase db,
  required ClinicalConfig config,
  required AppLocalizations l10n,
  required String profileId,
  required DateTime now,
}) async {
  final repo = ChildRepository(db);
  final reminders = <LocalReminder>[];
  for (final child in await repo.children()) {
    final doses = VaccineSchedule.build(
      config,
      birthDate: child.birthDate,
      done: const {},
      records: await repo.vaccineRecords(child.id),
      today: now,
    );
    for (final r in vaccineReminders(doses, now)) {
      final names = r.doses.map((d) => d.name).join(', ');
      final (title, body) = switch (r.kind) {
        VaccineReminderKind.weekBefore => (
          l10n.vaccineReminderWeekTitle(child.name),
          l10n.vaccineReminderWeekBody(formatDate(r.due), names),
        ),
        VaccineReminderKind.dayBefore => (
          l10n.vaccineReminderDayTitle(child.name),
          l10n.vaccineReminderDayBody(names),
        ),
        VaccineReminderKind.late => (
          l10n.vaccineReminderLateTitle(child.name),
          l10n.vaccineReminderLateBody(names),
        ),
      };
      reminders.add(LocalReminder(key: r.key(child.id), at: r.at, title: title, body: body));
    }
  }
  await LocalReminders.schedule(
    vaccineReminderGroup(profileId),
    reminders,
    channelName: l10n.vaccineReminderChannel,
    publicText: l10n.vaccineReminderPublic,
  );
}
