import '../../../core/config/clinical_config.dart';
import '../../../core/growth/who_lms.dart';

/// What the parent sees (spec §6): "Sur la bonne voie" / "À surveiller" /
/// "Consultez un agent de santé", read from `croissance.affichage_parent`.
///
/// The lowest available z-score decides (a child low on any indicator is
/// shown as such). Without any z-score (WHO tables missing) there is no
/// status: it is never guessed.
class ParentStatus {
  const ParentStatus(this.code, this.labels);
  final String code;
  final Map<String, Object?> labels;
}

abstract final class GrowthDisplay {
  static ParentStatus? status(ClinicalConfig config, ZScores z) {
    final values = [z.whz, z.waz, z.haz].whereType<double>().toList();
    if (values.isEmpty) return null;
    final lowest = values.reduce((a, b) => a < b ? a : b);
    for (final entry in asMapList(config.croissance['affichage_parent'])) {
      final min = asNum(entry['z_min']);
      if (min == null || lowest >= min) {
        return ParentStatus(entry['code']! as String, entry);
      }
    }
    return null;
  }

  /// z-score outside the plausible range of the config → "Vérifiez la mesure".
  static bool implausible(ClinicalConfig config, ZScores z) {
    final p = (config.malnutrition['plausibilite'] as Map?)?.cast<String, Object?>() ?? const {};
    final lo = asNum(p['z_min']);
    final hi = asNum(p['z_max']);
    if (lo == null || hi == null) return false;
    return [z.whz, z.waz, z.haz].any((v) => v != null && (v < lo || v > hi));
  }
}
