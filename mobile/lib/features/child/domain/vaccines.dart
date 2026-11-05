import '../../../core/config/clinical_config.dart';
import '../../../core/util/clock.dart';

enum DoseStatus { done, late, dueToday, upcoming }

class VaccineDose {
  const VaccineDose({
    required this.code,
    required this.name,
    required this.dueDate,
    required this.ageDays,
    required this.status,
    this.doneOn,
  });

  final String code;
  final String name;
  final DateTime dueDate;
  final int ageDays;
  final DoseStatus status;
  final DateTime? doneOn;
}

/// National immunisation schedule (PEV), read from `calendrier_pev` in the
/// configuration (spec §6: never hard-coded).
abstract final class VaccineSchedule {
  static List<VaccineDose> build(
    ClinicalConfig config, {
    required DateTime birthDate,
    required Map<String, DateTime> done,
    required DateTime today,
  }) {
    final t = dateOnly(today);
    final doses = [
      for (final d in asMapList(config.calendrierPev['doses']))
        () {
          final code = d['code']! as String;
          final age = asInt(d['age_jours']) ?? 0;
          final due = addDays(birthDate, age);
          final doneOn = done[code];
          final status = doneOn != null
              ? DoseStatus.done
              : t.isAfter(due)
              ? DoseStatus.late
              : (t == due ? DoseStatus.dueToday : DoseStatus.upcoming);
          return VaccineDose(
            code: code,
            name: (d['vaccin'] as String?) ?? code,
            dueDate: due,
            ageDays: age,
            status: status,
            doneOn: doneOn,
          );
        }(),
    ]..sort((a, b) => a.ageDays.compareTo(b.ageDays));
    return doses;
  }
}
