import '../../../core/config/clinical_config.dart';
import '../../../core/config/rule_engine.dart';
import '../../../core/growth/who_lms.dart';
import '../../../core/util/clock.dart';

/// What the community agent measures (spec §7).
class ScreeningInput {
  const ScreeningInput({
    required this.sex,
    required this.birthDate,
    required this.measureDate,
    required this.weightKg,
    required this.lengthCm,
    required this.position,
    this.muacMm,
    this.oedema = 'aucun',
    this.dangerSigns = const [],
    this.complications = false,
    this.appetite = 'non_teste',
    this.breastfeedingDifficulties = false,
  });

  /// 'M' or 'F'.
  final String sex;
  final DateTime birthDate;
  final DateTime measureDate;
  final double weightKg;
  final double lengthCm;

  /// 'couche' (lying) or 'debout' (standing).
  final String position;
  final int? muacMm;

  /// 'aucun', '+', '++', '+++'.
  final String oedema;
  final List<String> dangerSigns;
  final bool complications;

  /// 'non_teste', 'bon', 'mauvais'.
  final String appetite;
  final bool breastfeedingDifficulties;
}

enum ScreeningProblem { measureBeforeBirth, measureInFuture, muacOutsideAge, outsideAgeRange }

/// Values outside these bounds are almost certainly a typing error: the agent
/// is asked to check before saving. They are data-entry bounds, not clinical
/// thresholds (those come from the configuration).
abstract final class EntryBounds {
  static const double weightMinKg = 0.5;
  static const double weightMaxKg = 50;
  static const double lengthMinCm = 35;
  static const double lengthMaxCm = 140;
  static const int muacMinMm = 50;
  static const int muacMaxMm = 300;
}

class ScreeningResult {
  const ScreeningResult({
    required this.ageDays,
    required this.ageMonths,
    required this.correctedLengthCm,
    required this.zscores,
    required this.problems,
    required this.outOfBounds,
    required this.zOutOfRange,
    required this.classification,
    required this.centre,
    required this.urgence,
    required this.nextCheck,
    required this.adviceCode,
    required this.configVersion,
  });

  final int ageDays;
  final int ageMonths;
  final double correctedLengthCm;
  final ZScores zscores;

  /// Blocking problems: the measurement can't be saved as is.
  final List<ScreeningProblem> problems;

  /// "Vérifiez la mesure": raw value outside the entry bounds…
  final List<String> outOfBounds;

  /// …or a z-score outside the config's plausibility range (spec §6, §7).
  final bool zOutOfRange;

  /// `mas`, `mam`, `normal`, `nourrisson_a_risque` (config codes), or null
  /// outside the age range of the protocol.
  final String? classification;

  /// `creni`, `crenas`, `crenam`, `csb`, or null (no referral).
  final String? centre;

  /// `rouge`, `orange`, `jaune`, or null.
  final String? urgence;
  final DateTime? nextCheck;
  final String? adviceCode;
  final int configVersion;

  bool get needsCheck => outOfBounds.isNotEmpty || zOutOfRange;
  bool get needsReferral => centre != null;

  /// Referral `priorite` on the server (D5): rouge = urgente, orange = haute,
  /// jaune = normale.
  String get priorite => switch (urgence) {
    'rouge' => 'urgente',
    'orange' => 'haute',
    _ => 'normale',
  };

  /// The measurement's `alerte` traffic light (required by the API).
  String get alerte => switch (classification) {
    'mas' => 'rouge',
    'mam' || 'nourrisson_a_risque' => 'orange',
    _ => urgence == 'rouge' ? 'rouge' : 'vert',
  };
}

abstract final class ScreeningCalculator {
  /// Same constants as the server (`nutrition/services.py`).
  static const double daysPerMonth = 30.4375;
  static const double lengthCorrectionCm = 0.7;
  static const int muacMinMonths = 6;
  static const int muacMaxMonths = 59;

  static int ageDays(DateTime birth, DateTime on) => daysBetween(birth, on);

  static int ageMonths(int ageDays) => (ageDays / daysPerMonth).floor();

  /// Lying under 731 days, standing from 731 days: a measurement taken the
  /// other way is corrected by 0.7 cm (WHO), as the server does.
  static double correctedLength(double lengthCm, String position, int ageDays) {
    if (ageDays < GrowthMath.lengthToHeightDays && position == 'debout') {
      return _one(lengthCm + lengthCorrectionCm);
    }
    if (ageDays >= GrowthMath.lengthToHeightDays && position == 'couche') {
      return _one(lengthCm - lengthCorrectionCm);
    }
    return lengthCm;
  }

  static String defaultPosition(int ageDays) => ageDays < GrowthMath.lengthToHeightDays ? 'couche' : 'debout';

  static ScreeningResult compute(
    ScreeningInput input,
    ClinicalConfig config,
    WhoTables tables, {
    required DateTime today,
  }) {
    final days = ageDays(input.birthDate, input.measureDate);
    final months = days < 0 ? 0 : ageMonths(days);
    final corrected = correctedLength(input.lengthCm, input.position, days);
    final problems = <ScreeningProblem>[
      if (days < 0) ScreeningProblem.measureBeforeBirth,
      if (daysBetween(today, input.measureDate) > 0) ScreeningProblem.measureInFuture,
      if (input.muacMm != null && (months < muacMinMonths || months > muacMaxMonths))
        ScreeningProblem.muacOutsideAge,
    ];
    final mal = config.malnutrition;
    final maxMonths = asNum(mal['age_max_mois']) ?? 59;
    final minMonths = asNum(mal['age_min_mois']) ?? 0;
    if (days >= 0 && (months < minMonths || months > maxMonths)) {
      problems.add(ScreeningProblem.outsideAgeRange);
    }

    final outOfBounds = <String>[
      if (input.weightKg < EntryBounds.weightMinKg || input.weightKg > EntryBounds.weightMaxKg) 'poids_kg',
      if (input.lengthCm < EntryBounds.lengthMinCm || input.lengthCm > EntryBounds.lengthMaxCm) 'taille_cm',
      if (input.muacMm != null &&
          (input.muacMm! < EntryBounds.muacMinMm || input.muacMm! > EntryBounds.muacMaxMm))
        'pb_mm',
    ];

    final z = days < 0
        ? const ZScores()
        : GrowthMath.compute(
            tables,
            sex: input.sex,
            ageDays: days,
            weightKg: input.weightKg,
            correctedLengthCm: corrected,
          );
    final plaus = (mal['plausibilite'] as Map?)?.cast<String, Object?>() ?? const {};
    final zMin = asNum(plaus['z_min']);
    final zMax = asNum(plaus['z_max']);
    final zOut =
        zMin != null && zMax != null && [z.waz, z.haz, z.whz].any((v) => v != null && (v < zMin || v > zMax));

    final values = valuesFor(input, months, z);
    final classification = problems.isEmpty ? RuleEngine.classify(mal, values) : null;
    final rule = classification == null
        ? null
        : RuleEngine.orient(mal, {...values, 'classification': classification});
    final daysToCheck = asInt(rule?['prochain_controle_jours']);
    return ScreeningResult(
      ageDays: days,
      ageMonths: months,
      correctedLengthCm: corrected,
      zscores: z,
      problems: problems,
      outOfBounds: outOfBounds,
      zOutOfRange: zOut,
      classification: classification,
      centre: rule?['centre'] as String?,
      urgence: rule?['urgence'] as String?,
      nextCheck: daysToCheck == null ? null : dateOnly(input.measureDate).add(Duration(days: daysToCheck)),
      adviceCode: rule?['conseil'] as String?,
      configVersion: config.version,
    );
  }

  /// The named fields the rules can test (server: `regles.CHAMPS_MESURE`).
  static Map<String, Object?> valuesFor(ScreeningInput input, int months, ZScores z) => {
    'age_mois': months,
    'oedemes_bilateraux': input.oedema,
    'whz': z.whz,
    'waz': z.waz,
    'haz': z.haz,
    'pb_mm': input.muacMm,
    'signes_danger': input.dangerSigns,
    'complications_medicales': input.complications,
    'appetit': input.appetite,
    'difficultes_allaitement': input.breastfeedingDifficulties,
  };

  /// Short reason for the nurse, e.g. "MAS – PB 112 mm".
  static String motif(ScreeningInput input, ScreeningResult r) {
    final parts = <String>[
      if (input.muacMm != null) 'PB ${input.muacMm} mm',
      if (r.zscores.whz != null) 'P/T ${r.zscores.whz!.toStringAsFixed(2)} z',
      if (input.oedema != 'aucun') 'œdèmes ${input.oedema}',
      if (input.dangerSigns.isNotEmpty) 'signes de danger : ${input.dangerSigns.join(', ')}',
      if (input.complications) 'complication médicale',
      if (input.appetite == 'mauvais') 'appétit mauvais',
    ];
    final label = (r.classification ?? '').toUpperCase().replaceAll('_', ' ');
    return parts.isEmpty ? label : '$label – ${parts.join(' ; ')}';
  }

  static double _one(double v) => (v * 10).roundToDouble() / 10;
}
