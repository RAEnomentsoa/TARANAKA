import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/platform/file_saver.dart';
import '../../../core/platform/local_reminders.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../application/vaccine_reminders_sync.dart';
import '../data/child_repository.dart';
import '../domain/vaccines.dart';
import 'my_children_screen.dart';
import 'vaccine_record_screen.dart';

/// "Vaccins" (spec §6): the national schedule of the PEV Madagascar (from the
/// configuration), as a digital vaccination card.
///
/// From the top: the summary (received / to do / late, each with its colour,
/// icon and word), the next appointment, what to do when a vaccine is late,
/// then the late doses, the doses to do (by age, with their date) and the
/// doses received (date, centre, professional, checked on the card). A tap on
/// a dose records it or corrects it. The card can be downloaded as a file.
/// Reminders: 7 days before, the day before and when late.
class VaccinesScreen extends StatefulWidget {
  const VaccinesScreen({super.key, required this.childId});
  final String childId;

  @override
  State<VaccinesScreen> createState() => _VaccinesScreenState();
}

typedef _VaccinesData = (MyChild?, Map<String, VaccineRecord>, bool);

class _VaccinesScreenState extends State<VaccinesScreen> {
  Future<_VaccinesData>? _data;
  static const _askedKey = 'rappels_notifications_demandes';

  Future<_VaccinesData> _load() async {
    final repo = childRepository(context);
    return (
      await repo.child(widget.childId),
      await repo.vaccineRecords(widget.childId),
      await LocalReminders.allowed(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_data == null) {
      _data = _load();
      unawaited(_askNotificationsOnce());
    }
  }

  /// The first time: asks the phone to allow the reminders (Android 13+).
  Future<void> _askNotificationsOnce() async {
    final db = AppScope.read(context).session.active?.db;
    if (db == null || await db.getMeta(_askedKey) != null) return;
    await db.setMeta(_askedKey, '1');
    if (!await LocalReminders.allowed()) await LocalReminders.requestPermission();
    if (mounted) _reload();
  }

  Future<void> _enableReminders() async {
    await LocalReminders.requestPermission();
    if (mounted) _reload();
  }

  void _reload() {
    setState(() => _data = _load());
    _syncReminders();
  }

  void _syncReminders() {
    final scope = AppScope.read(context);
    final active = scope.session.active;
    if (active == null) return;
    unawaited(
      syncVaccineReminders(
        db: active.db,
        config: scope.services.config.current,
        l10n: context.l10n,
        profileId: active.info.id,
        now: scope.services.clock.now(),
      ).catchError((Object _) {}),
    );
  }

  Future<void> _open(MyChild child, VaccineDose dose, List<VaccineDose> all) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VaccineRecordScreen(child: child, dose: dose, all: all),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _export(MyChild child, List<VaccineDose> doses, ClinicalConfig config) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final text = vaccinationCardText(
      l10n,
      child: child,
      doses: doses,
      source: config.sourceLabel('calendrier_pev'),
      today: AppScope.read(context).services.clock.now(),
    );
    final safeName = child.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final ok = await TextFileSaver.save(fileName: 'taranaka-carnet-vaccination-$safeName.txt', text: text);
    messenger.showSnackBar(SnackBar(content: Text(ok ? l10n.vaccineCardSaved : l10n.vaccineCardNotSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    return FutureBuilder<_VaccinesData>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (child, records, notificationsOn) = snap.data!;
        if (child == null) return const Scaffold(body: ErrorView());
        final now = scope.services.clock.now();
        final doses = VaccineSchedule.build(
          config,
          birthDate: child.birthDate,
          done: const {},
          records: records,
          today: now,
        );
        final received = doses.where((d) => d.status == DoseStatus.done).toList()
          ..sort((a, b) => a.doneOn!.compareTo(b.doneOn!));
        final late = doses.where((d) => d.status == DoseStatus.late).toList();
        final toDo = doses.where((d) => d.isToDo).toList();
        final expired = doses.where((d) => d.status == DoseStatus.expired).toList();
        final next = VaccineSchedule.nextAppointment(doses, now);
        final advice = VaccineSchedule.catchUpAdvice(config);
        final text = Theme.of(context).textTheme;

        Widget tile(VaccineDose d) => _DoseTile(dose: d, onTap: () => _open(child, d, doses));

        final byAge = <int, List<VaccineDose>>{};
        for (final d in toDo) {
          byAge.putIfAbsent(d.ageDays, () => []).add(d);
        }

        return AppScreen(
          title: '${l10n.vaccines} – ${child.name}',
          actions: [
            IconButton(
              key: const ValueKey('vaccines-export-top'),
              tooltip: l10n.vaccineCardDownload,
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _export(child, doses, config),
            ),
          ],
          children: [
            Text(
              config.sourceLabel('calendrier_pev'),
              key: const ValueKey('vaccines-source'),
              style: text.bodySmall,
            ),
            const Gap(Space.m),
            // Summary: received / to do / late.
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                StatusPill(
                  key: const ValueKey('vaccines-count-done'),
                  icon: Icons.check_circle,
                  label: l10n.vaccinesCountDone(received.length),
                  tone: Tone.success,
                ),
                StatusPill(
                  key: const ValueKey('vaccines-count-todo'),
                  icon: Icons.schedule,
                  label: l10n.vaccinesCountToDo(toDo.length),
                  tone: Tone.info,
                ),
                StatusPill(
                  key: const ValueKey('vaccines-count-late'),
                  icon: Icons.error,
                  label: l10n.vaccinesCountLate(late.length),
                  tone: late.isEmpty ? Tone.neutral : Tone.warning,
                ),
              ],
            ),
            const Gap(Space.m),
            if (next != null) _nextCard(context, next, late.isNotEmpty),
            if (late.isNotEmpty) ...[
              const Gap(Space.s),
              NoticeBox(
                key: const ValueKey('vaccines-late-notice'),
                icon: Icons.error_outline,
                tone: Tone.warning,
                text: l10n.vaccinesLateNotice(late.length),
              ),
            ],
            if (advice.isNotEmpty)
              ExpansionTile(
                key: const ValueKey('vaccines-catchup'),
                initiallyExpanded: late.isNotEmpty,
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(Icons.help_outline, color: AppColors.warning),
                title: Text(l10n.vaccinesCatchUpTitle, style: text.titleSmall),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                childrenPadding: const EdgeInsets.only(bottom: Space.s),
                children: [
                  for (final a in advice)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.check, size: 18, color: AppColors.textMuted),
                          ),
                          const SizedBox(width: Space.s),
                          Expanded(child: Text(a)),
                        ],
                      ),
                    ),
                  Text(
                    l10n.vaccinesCatchUpSource,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            // Reminders: on, or how to turn them on.
            if (notificationsOn)
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      l10n.vaccineRemindersOn,
                      key: const ValueKey('vaccines-reminders-on'),
                      style: text.bodySmall,
                    ),
                  ),
                ],
              )
            else
              NoticeBox(
                key: const ValueKey('vaccines-reminders-off'),
                icon: Icons.notifications_off_outlined,
                text: l10n.vaccineRemindersOff,
                onTap: _enableReminders,
              ),
            if (late.isNotEmpty) ...[SectionTitle(l10n.vaccinesSectionLate), for (final d in late) tile(d)],
            if (toDo.isNotEmpty) ...[
              SectionTitle(l10n.vaccinesSectionToDo),
              for (final MapEntry(key: age, value: group) in byAge.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: Space.s, bottom: Space.xs),
                  child: Text(
                    '${l10n.vaccineAtAge(_age(context, age))} · ${formatDate(group.first.dueDate)}',
                    style: text.titleSmall?.copyWith(color: AppColors.accent),
                  ),
                ),
                for (final d in group) tile(d),
              ],
            ],
            SectionTitle(l10n.vaccinesSectionDone),
            if (received.isEmpty)
              Text(l10n.vaccinesNoneDone, style: text.bodyMedium)
            else
              for (final d in received) tile(d),
            if (expired.isNotEmpty) ...[
              SectionTitle(l10n.vaccinesSectionExpired),
              for (final d in expired) tile(d),
            ],
            const Gap(Space.l),
            OutlinedButton.icon(
              key: const ValueKey('vaccines-export'),
              onPressed: () => _export(child, doses, config),
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.vaccineCardDownload),
            ),
            const Gap(Space.s),
            Text(l10n.vaccineCardNote, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
          ],
        );
      },
    );
  }

  Widget _nextCard(BuildContext context, (DateTime, List<VaccineDose>) next, bool late) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final (date, doses) = next;
    final tone = late ? Tone.warning : Tone.info;
    return Container(
      key: const ValueKey('vaccines-next'),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(Radii.m),
        border: Border.all(color: tone.foreground.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_available_outlined, color: tone.foreground),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.vaccinesNext, style: text.labelLarge?.copyWith(color: tone.foreground)),
                Text(
                  late ? l10n.vaccinesNextAsap : formatDate(date),
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(doses.map((d) => d.name).join(', ')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _age(BuildContext context, int days) {
  final l10n = context.l10n;
  return days == 0
      ? l10n.atBirth
      : days < 180
      ? l10n.weeksAge(days ~/ 7)
      : l10n.childAge((days / 30.4375).round());
}

/// One dose: name, what it protects against, its status (colour + icon +
/// word) and, once received, where, by whom and whether the card says so.
class _DoseTile extends StatelessWidget {
  const _DoseTile({required this.dose, required this.onTap});

  final VaccineDose dose;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final d = dose;
    final r = d.record;
    final (icon, tone) = vaccineStatusLook(d.status);
    return Card(
      key: ValueKey('vaccine-${d.code}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.s, Space.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tone.foreground),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: text.titleSmall),
                    if (d.protects.isNotEmpty)
                      Text(d.protects, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                    const Gap(Space.xs),
                    vaccineStatusPill(context, d),
                    if (r != null) ...[
                      if (r.centre.isNotEmpty) _line(context, Icons.local_hospital_outlined, r.centre),
                      if (r.professional.isNotEmpty) _line(context, Icons.person_outline, r.professional),
                      if (r.confirmedByCard != null)
                        _line(
                          context,
                          r.confirmedByCard! ? Icons.fact_check_outlined : Icons.help_outline,
                          l10n.vaccineCardConfirmed(r.confirmedByCard! ? l10n.yes : l10n.no),
                        ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String value) => Padding(
    padding: const EdgeInsets.only(top: Space.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: Space.xs),
        Expanded(child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
      ],
    ),
  );
}

/// Icon and colour of each status: green received, blue to do, orange late,
/// grey no longer given (always with a word too).
(IconData, Tone) vaccineStatusLook(DoseStatus s) => switch (s) {
  DoseStatus.done => (Icons.check_circle, Tone.success),
  DoseStatus.dueToday || DoseStatus.upcoming => (Icons.schedule, Tone.info),
  DoseStatus.late => (Icons.error, Tone.warning),
  DoseStatus.expired => (Icons.block, Tone.neutral),
};

Widget vaccineStatusPill(BuildContext context, VaccineDose d) {
  final l10n = context.l10n;
  final (icon, tone) = vaccineStatusLook(d.status);
  final label = switch (d.status) {
    DoseStatus.done => l10n.vaccineDone(formatDate(d.doneOn!)),
    DoseStatus.late => l10n.vaccineLate(formatDate(d.dueDate)),
    DoseStatus.dueToday => l10n.vaccineDueToday,
    DoseStatus.upcoming => l10n.vaccineUpcoming(formatDate(d.dueDate)),
    DoseStatus.expired => l10n.vaccineExpired,
  };
  return StatusPill(key: ValueKey('vaccine-status-${d.code}'), icon: icon, label: label, tone: tone);
}

/// The vaccination card as plain text (downloaded with "Enregistrer sous").
String vaccinationCardText(
  AppLocalizations l10n, {
  required MyChild child,
  required List<VaccineDose> doses,
  required String source,
  required DateTime today,
}) {
  String doseLine(VaccineDose d) {
    final r = d.record;
    return [
      '- ${d.name}',
      switch (d.status) {
        DoseStatus.done => l10n.vaccineDone(formatDate(d.doneOn!)),
        DoseStatus.late => l10n.vaccineLate(formatDate(d.dueDate)),
        DoseStatus.dueToday => l10n.vaccineDueToday,
        DoseStatus.upcoming => l10n.vaccineUpcoming(formatDate(d.dueDate)),
        DoseStatus.expired => l10n.vaccineExpired,
      },
      if (r != null && r.centre.isNotEmpty) r.centre,
      if (r != null && r.professional.isNotEmpty) r.professional,
      if (r?.confirmedByCard != null) l10n.vaccineCardConfirmed(r!.confirmedByCard! ? l10n.yes : l10n.no),
    ].join(' · ');
  }

  final received = doses.where((d) => d.status == DoseStatus.done).toList();
  final late = doses.where((d) => d.status == DoseStatus.late).toList();
  final toDo = doses.where((d) => d.isToDo).toList();
  return [
    l10n.vaccineCardFileTitle,
    l10n.vaccineCardFileChild(child.name, formatDate(child.birthDate)),
    source,
    l10n.vaccineCardFileDate(formatDate(today)),
    '',
    l10n.vaccinesSectionDone.toUpperCase(),
    if (received.isEmpty) '-' else ...received.map(doseLine),
    '',
    if (late.isNotEmpty) ...[l10n.vaccinesSectionLate.toUpperCase(), ...late.map(doseLine), ''],
    if (toDo.isNotEmpty) ...[l10n.vaccinesSectionToDo.toUpperCase(), ...toDo.map(doseLine), ''],
    l10n.vaccineCardNote,
  ].join('\n');
}
