import '../../../core/config/clinical_config.dart';
import '../../../core/util/clock.dart';

/// Gestational age in weeks of amenorrhoea (SA) + days.
class GestationalAge {
  const GestationalAge(this.totalDays);
  final int totalDays;

  int get weeks => totalDays ~/ 7;
  int get days => totalDays % 7;
}

/// A pregnancy as entered by the woman (spec §5): last menstrual period (DDR)
/// and/or a term confirmed by a professional (ultrasound or consultation),
/// expressed as a gestational age on the day of the exam.
class PregnancyDates {
  const PregnancyDates({this.lmp, this.confirmedOn, this.confirmedAgeDays, this.deliveredOn});

  final DateTime? lmp;
  final DateTime? confirmedOn;
  final int? confirmedAgeDays;
  final DateTime? deliveredOn;

  bool get hasConfirmedTerm => confirmedOn != null && confirmedAgeDays != null;
}

enum ContactStatus { done, missed, next, upcoming }

class CareContact {
  const CareContact({
    required this.number,
    required this.date,
    required this.label,
    required this.status,
    this.doneOn,
  });

  /// 1-based, as in the national calendar.
  final int number;
  final DateTime date;

  /// SA for antenatal contacts, days after birth for postnatal ones.
  final int label;
  final ContactStatus status;
  final DateTime? doneOn;
}

/// Calculations of "Ma grossesse". Durations and calendars come from the
/// configuration (`grossesse`, `calendrier_cpn`, `calendrier_postnatal`).
class PregnancyCalculator {
  PregnancyCalculator(this.config);

  final ClinicalConfig config;

  Map<String, Object?> get _g => config.grossesse;

  /// Naegele: DDR + 280 days in the sample configuration.
  int get naegeleDays => asInt(_g['duree_naegele_jours']) ?? 280;
  bool get confirmedTermWins => _g['terme_confirme_prioritaire'] != false;
  int get movementsFromWeeks => asInt(_g['journal_mouvements_a_partir_sa']) ?? 28;
  List<int> get firstMovementsWeeks =>
      (_g['premiers_mouvements_sa'] as List?)?.map((e) => asInt(e)!).toList() ?? const [16, 22];

  /// Day 0 of the pregnancy dating: the DDR, or the date implied by the
  /// confirmed term (which wins when the configuration says so).
  DateTime? referenceDate(PregnancyDates p) {
    final confirmed = p.hasConfirmedTerm ? addDays(p.confirmedOn!, -p.confirmedAgeDays!) : null;
    if (confirmed != null && (confirmedTermWins || p.lmp == null)) return confirmed;
    return p.lmp == null ? confirmed : dateOnly(p.lmp!);
  }

  GestationalAge? age(PregnancyDates p, DateTime today) {
    final ref = referenceDate(p);
    if (ref == null) return null;
    return GestationalAge(daysBetween(ref, today));
  }

  /// Date probable d'accouchement.
  DateTime? dueDate(PregnancyDates p) => () {
    final ref = referenceDate(p);
    return ref == null ? null : addDays(ref, naegeleDays);
  }();

  /// Trimester from completed weeks: 1st until 13 SA + 6 d, 2nd until 27 SA + 6 d,
  /// then 3rd. These are the usual obstetric definitions, read from the
  /// configuration when it provides `grossesse.trimestres_debut_sa`.
  int trimester(GestationalAge ga) {
    final starts = (_g['trimestres_debut_sa'] as List?)?.map((e) => asInt(e)!).toList() ?? const [0, 14, 28];
    var t = 1;
    for (var i = 0; i < starts.length; i++) {
      if (ga.weeks >= starts[i]) t = i + 1;
    }
    return t;
  }

  bool movementsLogOpen(GestationalAge ga) => ga.weeks >= movementsFromWeeks;

  /// Antenatal contacts (spec §5: OMS 2016, 8 contacts; dates from the
  /// national calendar in the configuration).
  List<CareContact> antenatal(PregnancyDates p, Map<int, DateTime> done, DateTime today) {
    final ref = referenceDate(p);
    if (ref == null) return const [];
    final weeks =
        (config.calendrierCpn['contacts_semaines_amenorrhee'] as List?)?.map((e) => asInt(e)!).toList() ??
        const <int>[];
    return _contacts([for (final w in weeks) (w, addDays(ref, w * 7))], done, today);
  }

  /// Postnatal contacts after the delivery (OMS 2022: at least 4 in 6 weeks).
  List<CareContact> postnatal(PregnancyDates p, Map<int, DateTime> done, DateTime today) {
    final birth = p.deliveredOn;
    if (birth == null) return const [];
    final days =
        (config.calendrierPostnatal['contacts_jours_apres_accouchement'] as List?)
            ?.map((e) => asInt(e)!)
            .toList() ??
        const <int>[];
    return _contacts([for (final d in days) (d, addDays(birth, d))], done, today);
  }

  List<CareContact> _contacts(List<(int, DateTime)> planned, Map<int, DateTime> done, DateTime today) {
    final t = dateOnly(today);
    var nextGiven = false;
    return [
      for (var i = 0; i < planned.length; i++)
        () {
          final number = i + 1;
          final (label, date) = planned[i];
          ContactStatus status;
          if (done.containsKey(number)) {
            status = ContactStatus.done;
          } else if (date.isBefore(t)) {
            status = ContactStatus.missed;
          } else if (!nextGiven) {
            status = ContactStatus.next;
            nextGiven = true;
          } else {
            status = ContactStatus.upcoming;
          }
          return CareContact(number: number, date: date, label: label, status: status, doneOn: done[number]);
        }(),
    ];
  }
}

/// Women's dietary diversity (MDD-W, 10 groups, optional; spec §5).
class WomenDiet {
  WomenDiet(this.config);
  final ClinicalConfig config;

  List<String> get groups => (config.alimentationFemme['groupes'] as List?)?.cast<String>() ?? const [];
  int get minimum => asInt(config.alimentationFemme['diversite_minimale_groupes']) ?? 5;

  bool met(Set<int> eaten) => eaten.length >= minimum;
}
