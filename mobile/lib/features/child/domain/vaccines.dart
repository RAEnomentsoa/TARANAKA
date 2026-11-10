import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/language.dart';
import '../../../core/util/clock.dart';

/// "Vaccin reçu" (green), "À faire" (blue: today or later), "En retard"
/// (orange). [expired]: the dose is no longer given at this age (VPO 0 after
/// 14 days, Rotavirus after 24 months…): nothing to catch up, see the advice.
enum DoseStatus { done, late, dueToday, upcoming, expired }

/// A dose received, as written on the vaccination card.
class VaccineRecord {
  const VaccineRecord({
    required this.code,
    required this.date,
    this.centre = '',
    this.professional = '',
    this.confirmedByCard,
  });

  final String code;

  /// Real date of the vaccination.
  final DateTime date;
  final String centre;
  final String professional;

  /// "Confirmé par le carnet de vaccination : Oui / Non" (null: not said).
  final bool? confirmedByCard;
}

class VaccineDose {
  const VaccineDose({
    required this.code,
    required this.name,
    required this.dueDate,
    required this.ageDays,
    required this.status,
    this.doneOn,
    this.record,
    this.protects = '',
    this.route = '',
    this.lateAfter,
    this.lastDay,
    this.after,
    this.minIntervalDays = 0,
  });

  final String code;
  final String name;

  /// Date planned by the schedule (birth + age).
  final DateTime dueDate;
  final int ageDays;
  final DoseStatus status;
  final DateTime? doneOn;
  final VaccineRecord? record;

  /// What it protects against, and how it is given (configuration).
  final String protects;
  final String route;

  /// "En retard" after this day (end of the national window, else the due date).
  final DateTime? lateAfter;

  /// Last day the dose can still be given (null: no limit).
  final DateTime? lastDay;

  /// Previous dose of the same series, and the minimum gap after it.
  final String? after;
  final int minIntervalDays;

  bool get isToDo => status == DoseStatus.dueToday || status == DoseStatus.upcoming;
}

/// What looks wrong with a date entered for a dose (asked to check, not
/// refused: the card is what counts).
enum DoseDateIssue { beforeBirth, inFuture, beforeMinAge, tooSoonAfterPrevious, afterLastDay }

/// National immunisation schedule (PEV Madagascar), read from
/// `calendrier_pev` in the configuration (spec §6: never hard-coded).
abstract final class VaccineSchedule {
  static List<VaccineDose> build(
    ClinicalConfig config, {
    required DateTime birthDate,
    required Map<String, DateTime> done,
    required DateTime today,
    Map<String, VaccineRecord> records = const {},
  }) {
    final t = dateOnly(today);
    final birth = dateOnly(birthDate);
    final doses = [
      for (final d in asMapList(config.calendrierPev['doses']))
        () {
          final code = d['code']! as String;
          // Doses saved under a former code of the schedule (e.g. "rr1").
          final codes = [code, ...((d['anciens_codes'] as List?) ?? const []).whereType<String>()];
          final record = codes.map((c) => records[c]).nonNulls.firstOrNull;
          final doneOn = record?.date ?? codes.map((c) => done[c]).nonNulls.firstOrNull;
          final age = asInt(d['age_jours']) ?? 0;
          final due = addDays(birth, age);
          final windowEnd = asInt(d['fin_fenetre_jours']);
          final lateAfter = windowEnd == null ? due : addDays(birth, windowEnd);
          final maxAge = asInt(d['age_max_jours']);
          final lastDay = maxAge == null ? null : addDays(birth, maxAge);
          final status = doneOn != null
              ? DoseStatus.done
              : lastDay != null && t.isAfter(lastDay)
              ? DoseStatus.expired
              : t.isAfter(lateAfter)
              ? DoseStatus.late
              : (t == due ? DoseStatus.dueToday : DoseStatus.upcoming);
          return VaccineDose(
            code: code,
            name: (d['vaccin'] as String?) ?? code,
            dueDate: due,
            ageDays: age,
            status: status,
            doneOn: doneOn,
            record: record == null
                ? null
                : VaccineRecord(
                    code: code,
                    date: record.date,
                    centre: record.centre,
                    professional: record.professional,
                    confirmedByCard: record.confirmedByCard,
                  ),
            protects: localizedText(d['protege'], appLanguage),
            route: localizedText(d['voie'], appLanguage),
            lateAfter: lateAfter,
            lastDay: lastDay,
            after: d['apres'] as String?,
            minIntervalDays: asInt(d['intervalle_min_jours']) ?? 0,
          );
        }(),
    ]..sort((a, b) => a.ageDays.compareTo(b.ageDays));
    return doses;
  }

  /// The catch-up advice of the PEV (configuration), in the app language.
  static List<String> catchUpAdvice(ClinicalConfig config) => [
    for (final a in (config.calendrierPev['rattrapage'] as List?) ?? const []) localizedText(a, appLanguage),
  ].where((s) => s.isNotEmpty).toList();

  /// Checks a date entered for [dose]; empty when it looks right.
  static List<DoseDateIssue> checkDate(
    VaccineDose dose,
    DateTime date, {
    required DateTime birthDate,
    required DateTime today,
    required List<VaccineDose> all,
  }) {
    final d = dateOnly(date);
    final issues = <DoseDateIssue>[];
    if (d.isBefore(dateOnly(birthDate))) issues.add(DoseDateIssue.beforeBirth);
    if (d.isAfter(dateOnly(today))) issues.add(DoseDateIssue.inFuture);
    // The schedule says "at 6 weeks": a few days early is usual, weeks are not.
    if (dose.ageDays > 0 && d.isBefore(addDays(dose.dueDate, -7)) && !d.isBefore(dateOnly(birthDate))) {
      issues.add(DoseDateIssue.beforeMinAge);
    }
    final previous = all.where((x) => x.code == dose.after).firstOrNull;
    if (previous?.doneOn != null && d.isBefore(addDays(previous!.doneOn!, dose.minIntervalDays))) {
      issues.add(DoseDateIssue.tooSoonAfterPrevious);
    }
    if (dose.lastDay != null && d.isAfter(dose.lastDay!)) issues.add(DoseDateIssue.afterLastDay);
    return issues;
  }

  /// The next appointment: the earliest date with doses still to do (late
  /// ones first: "dès que possible"), with its doses.
  static (DateTime, List<VaccineDose>)? nextAppointment(List<VaccineDose> doses, DateTime today) {
    final open = doses.where((d) => d.status == DoseStatus.late || d.isToDo).toList();
    if (open.isEmpty) return null;
    final late = open.where((d) => d.status == DoseStatus.late).toList();
    if (late.isNotEmpty) return (dateOnly(today), late);
    final first = open.map((d) => d.dueDate).reduce((a, b) => a.isBefore(b) ? a : b);
    return (first, open.where((d) => d.dueDate == first).toList());
  }
}

/// A local reminder ("rappel") to show at [at].
class VaccineReminder {
  const VaccineReminder({required this.kind, required this.at, required this.due, required this.doses});

  final VaccineReminderKind kind;
  final DateTime at;

  /// Date of the doses (planned date).
  final DateTime due;
  final List<VaccineDose> doses;

  /// Stable key: one reminder per kind and date for a child.
  String key(String childId) =>
      'vaccin-$childId-${kind.name}-${dateOnly(due).toIso8601String().substring(0, 10)}';
}

enum VaccineReminderKind { weekBefore, dayBefore, late }

/// Reminders 7 days before, the day before, and when late (the day after the
/// end of the window, then every week for 8 weeks), at [hour] o'clock. Only
/// those still to come.
List<VaccineReminder> vaccineReminders(List<VaccineDose> doses, DateTime now, {int hour = 9}) {
  final byDue = <DateTime, List<VaccineDose>>{};
  for (final d in doses.where((d) => d.status != DoseStatus.done && d.status != DoseStatus.expired)) {
    (byDue[d.dueDate] ??= []).add(d);
  }
  DateTime at(DateTime day) => DateTime(day.year, day.month, day.day, hour);
  final out = <VaccineReminder>[];
  for (final MapEntry(key: due, value: group) in byDue.entries) {
    for (final (kind, day) in [
      (VaccineReminderKind.weekBefore, addDays(due, -7)),
      (VaccineReminderKind.dayBefore, addDays(due, -1)),
    ]) {
      if (at(day).isAfter(now)) out.add(VaccineReminder(kind: kind, at: at(day), due: due, doses: group));
    }
    // Late: the first weekly reminder still to come (not before the end of
    // the window, not after the last day the doses can be given).
    final lateAfter = group.map((d) => d.lateAfter ?? due).reduce((a, b) => a.isAfter(b) ? a : b);
    for (var week = 0; week < 8; week++) {
      final day = addDays(lateAfter, 1 + 7 * week);
      final lastDays = group.map((d) => d.lastDay).nonNulls;
      if (lastDays.isNotEmpty && lastDays.every((l) => day.isAfter(l))) break;
      if (at(day).isAfter(now)) {
        out.add(VaccineReminder(kind: VaccineReminderKind.late, at: at(day), due: due, doses: group));
        break;
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}
