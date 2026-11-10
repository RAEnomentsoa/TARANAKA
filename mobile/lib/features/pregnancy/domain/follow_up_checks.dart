import '../../../core/config/clinical_config.dart';
import 'pregnancy.dart';

/// How worrying a value of "Mon suivi de grossesse" is. Shown with an icon
/// and a word as well as a colour (never colour alone).
enum FlagLevel {
  /// Go now (red): opens the red alert.
  urgent,

  /// See a health worker today (orange).
  warning,

  /// Good to know, to watch (blue).
  info,
}

/// What was detected; the screens give the matching title and advice.
enum FlagKind {
  bpSevere(FlagLevel.urgent),
  bpHigh(FlagLevel.warning),
  bpLow(FlagLevel.info),
  feverHigh(FlagLevel.urgent),
  fever(FlagLevel.warning),
  glucoseLow(FlagLevel.urgent),
  glucoseVeryHigh(FlagLevel.warning),
  glucoseHighFasting(FlagLevel.warning),
  glucoseToCheck(FlagLevel.info),
  anaemiaSevere(FlagLevel.urgent),
  anaemia(FlagLevel.warning),

  /// Headache or blurred vision with a high blood pressure.
  preEclampsiaUrgent(FlagLevel.urgent),

  /// Headache or blurred vision: measure the blood pressure, consult today.
  preEclampsiaSigns(FlagLevel.warning),
  breathless(FlagLevel.warning),

  /// Dizziness: get up slowly, drink; consult if it lasts.
  dizzy(FlagLevel.info);

  const FlagKind(this.level);
  final FlagLevel level;
}

/// The quick symptoms of "Ce que je ressens" (labels in the l10n
/// `quickSymptoms`, same order).
enum QuickSymptom { dizziness, fatigue, breathless, headache, blurredVision, pain }

/// Limits used to read the values of "Mon suivi de grossesse". From
/// `grossesse` in the configuration when it has them; otherwise usual values
/// for pregnancy (WHO, to be validated by the health team like the rest of
/// the clinical content).
class FollowUpLimits {
  FollowUpLimits(ClinicalConfig config) : _g = config.grossesse, _calc = PregnancyCalculator(config);

  final Map<String, Object?> _g;
  final PregnancyCalculator _calc;

  int get highSystolic => _calc.highSystolic;
  int get highDiastolic => _calc.highDiastolic;
  int get severeSystolic => asInt(_g['tension_severe_systolique']) ?? 160;
  int get severeDiastolic => asInt(_g['tension_severe_diastolique']) ?? 110;
  int get lowSystolic => asInt(_g['tension_basse_systolique']) ?? 90;
  int get lowDiastolic => asInt(_g['tension_basse_diastolique']) ?? 60;
  double get feverFrom => _calc.feverFrom;
  double get highFeverFrom => asNum(_g['fievre_forte_a_partir_c'])?.toDouble() ?? 39;

  /// g/L.
  double get glucoseLow => asNum(_g['glycemie_basse_g_l'])?.toDouble() ?? 0.60;
  double get glucoseFastingHigh => asNum(_g['glycemie_jeun_max_g_l'])?.toDouble() ?? 0.92;
  double get glucoseRandomCheck => asNum(_g['glycemie_controle_g_l'])?.toDouble() ?? 1.40;
  double get glucoseVeryHigh => asNum(_g['glycemie_tres_elevee_g_l'])?.toDouble() ?? 2.00;

  /// g/dL.
  double get anaemiaBelow => asNum(_g['anemie_hb_sous_g_dl'])?.toDouble() ?? 11;
  double get severeAnaemiaBelow => asNum(_g['anemie_severe_hb_sous_g_dl'])?.toDouble() ?? 7;
}

/// The worrying values of one entry, most serious first.
///
/// [glucoseFasting]: null when not said (then only the clear limits apply).
/// [symptoms]: the quick symptoms chosen with the entry.
List<FlagKind> assessFollowUp(
  FollowUpLimits limits, {
  int? systolic,
  int? diastolic,
  double? temperatureC,
  double? glucoseGl,
  bool? glucoseFasting,
  double? hemoglobinGdl,
  Set<QuickSymptom> symptoms = const {},
}) {
  final flags = <FlagKind>[];
  final bpHigh =
      systolic != null &&
      diastolic != null &&
      (systolic >= limits.highSystolic || diastolic >= limits.highDiastolic);
  if (systolic != null && diastolic != null) {
    if (systolic >= limits.severeSystolic || diastolic >= limits.severeDiastolic) {
      flags.add(FlagKind.bpSevere);
    } else if (bpHigh) {
      flags.add(FlagKind.bpHigh);
    } else if (systolic < limits.lowSystolic || diastolic < limits.lowDiastolic) {
      flags.add(FlagKind.bpLow);
    }
  }
  final preEclampsiaSign =
      symptoms.contains(QuickSymptom.headache) || symptoms.contains(QuickSymptom.blurredVision);
  if (preEclampsiaSign) flags.add(bpHigh ? FlagKind.preEclampsiaUrgent : FlagKind.preEclampsiaSigns);
  if (temperatureC != null) {
    if (temperatureC >= limits.highFeverFrom) {
      flags.add(FlagKind.feverHigh);
    } else if (temperatureC >= limits.feverFrom) {
      flags.add(FlagKind.fever);
    }
  }
  if (glucoseGl != null) {
    if (glucoseGl < limits.glucoseLow) {
      flags.add(FlagKind.glucoseLow);
    } else if (glucoseGl >= limits.glucoseVeryHigh) {
      flags.add(FlagKind.glucoseVeryHigh);
    } else if (glucoseFasting == true && glucoseGl >= limits.glucoseFastingHigh) {
      flags.add(FlagKind.glucoseHighFasting);
    } else if (glucoseFasting != true && glucoseGl >= limits.glucoseRandomCheck) {
      flags.add(FlagKind.glucoseToCheck);
    }
  }
  if (hemoglobinGdl != null) {
    if (hemoglobinGdl < limits.severeAnaemiaBelow) {
      flags.add(FlagKind.anaemiaSevere);
    } else if (hemoglobinGdl < limits.anaemiaBelow) {
      flags.add(FlagKind.anaemia);
    }
  }
  if (symptoms.contains(QuickSymptom.breathless)) flags.add(FlagKind.breathless);
  if (symptoms.contains(QuickSymptom.dizziness)) flags.add(FlagKind.dizzy);
  flags.sort((a, b) => a.level.index.compareTo(b.level.index));
  return flags;
}

/// A point of a chart: the term (weeks, with days as a fraction) and value.
class TrendPoint {
  const TrendPoint(this.weeks, this.value);
  final double weeks;
  final double value;
}
