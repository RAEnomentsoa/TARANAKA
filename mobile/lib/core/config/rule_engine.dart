import 'clinical_config.dart';

/// Reads the declarative rules of the clinical configuration.
///
/// Same semantics as the server (`Backend_serveur/config_clinique/regles.py`),
/// so the phone and the server classify a measurement the same way:
/// - rules are read in order, the first one that applies wins;
/// - `age_mois_min` / `age_mois_max`, `si_classification`, `si_un_des`, `si_tous`;
/// - operators `inferieur_a`, `inferieur_ou_egal_a`, `superieur_a`,
///   `superieur_ou_egal_a`, `egal`, `dans`, `non_vide`;
/// - a condition on a missing value is false (an unknown z-score never
///   triggers a rule by itself).
///
/// The code holds no threshold, no destination and no delay.
abstract final class RuleEngine {
  static bool condition(Map<String, Object?> condition, Map<String, Object?> values) {
    final value = values[condition['champ']];
    if (condition.containsKey('non_vide')) {
      return _truthy(value) == condition['non_vide'];
    }
    if (value == null) return false;
    for (final op in const ['inferieur_a', 'inferieur_ou_egal_a', 'superieur_a', 'superieur_ou_egal_a']) {
      if (condition.containsKey(op)) {
        final a = _number(value);
        final b = _number(condition[op]);
        if (a == null || b == null) return false;
        return switch (op) {
          'inferieur_a' => a < b,
          'inferieur_ou_egal_a' => a <= b,
          'superieur_a' => a > b,
          _ => a >= b,
        };
      }
    }
    if (condition.containsKey('egal')) return _equal(value, condition['egal']);
    if (condition.containsKey('dans')) {
      final list = condition['dans'];
      return list is List && list.any((e) => _equal(value, e));
    }
    return false;
  }

  static bool applies(Map<String, Object?> rule, Map<String, Object?> values) {
    final age = _number(values['age_mois']);
    if (rule.containsKey('age_mois_min') && (age == null || age < (_number(rule['age_mois_min']) ?? 0))) {
      return false;
    }
    if (rule.containsKey('age_mois_max') && (age == null || age > (_number(rule['age_mois_max']) ?? 0))) {
      return false;
    }
    final classifications = rule['si_classification'];
    if (classifications is List && !classifications.contains(values['classification'])) {
      return false;
    }
    final anyOf = rule['si_un_des'];
    if (anyOf is List && !asMapList(anyOf).any((c) => condition(c, values))) return false;
    final allOf = rule['si_tous'];
    if (allOf is List && !asMapList(allOf).every((c) => condition(c, values))) return false;
    return true;
  }

  static Map<String, Object?>? firstRule(Object? rules, Map<String, Object?> values) {
    for (final rule in asMapList(rules)) {
      if (applies(rule, values)) return rule;
    }
    return null;
  }

  /// MAS / MAM / normal / at-risk infant, or null outside the age range.
  static String? classify(Map<String, Object?> malnutrition, Map<String, Object?> values) {
    final age = _number(values['age_mois']);
    final min = _number(malnutrition['age_min_mois']) ?? 0;
    final max = _number(malnutrition['age_max_mois']);
    if (age == null || max == null || age < min || age > max) return null;
    final classification = (malnutrition['classification'] as Map?)?.cast<String, Object?>();
    if (classification == null) return null;
    final rule = firstRule(classification['regles'], values);
    return (rule?['code'] ?? classification['par_defaut']) as String?;
  }

  /// The orientation rule for a classified child, or null.
  static Map<String, Object?>? orient(Map<String, Object?> malnutrition, Map<String, Object?> values) {
    final c = values['classification'];
    if (c == null || c == '') return null;
    return firstRule((malnutrition['orientation'] as Map?)?['regles'], values);
  }

  static num? _number(Object? v) => v is num ? v : (v is String ? num.tryParse(v) : null);

  static bool _equal(Object? a, Object? b) => a == b;

  /// Python truthiness, as `bool(valeur)` in regles.py.
  static bool _truthy(Object? v) => switch (v) {
    null => false,
    final bool b => b,
    final num n => n != 0,
    final String s => s.isNotEmpty,
    final Iterable<Object?> i => i.isNotEmpty,
    final Map<Object?, Object?> m => m.isNotEmpty,
    _ => true,
  };
}
