import '../i18n/language.dart';

/// The versioned clinical configuration (spec §11).
///
/// Thresholds, calendars, danger signs and advice live here, never in code.
/// The bundled version is the backend's sample, marked "À VALIDER"; newer
/// versions arrive with `/api/sync/pull/`.
class ClinicalConfig {
  ClinicalConfig({
    required this.version,
    required this.statutValidation,
    required this.contenu,
    this.libelle = '',
  });

  final int version;

  /// `a_valider` or `validee` (server field `statut_validation`).
  final String statutValidation;
  final String libelle;
  final Map<String, Object?> contenu;

  /// True until the Ministry / ONN / medical committee has signed the version.
  bool get toValidate =>
      statutValidation != 'validee' ||
      (meta['statut_validation'] as String?)?.toUpperCase().contains('VALIDER') == true;

  Map<String, Object?> get meta => section('meta');

  Map<String, Object?> section(String name) => (contenu[name] as Map?)?.cast<String, Object?>() ?? const {};

  Map<String, Object?> get malnutrition => section('malnutrition');
  Map<String, Object?> get croissance => section('croissance');
  Map<String, Object?> get signesDanger => section('signes_danger');
  Map<String, Object?> get calendrierPev => section('calendrier_pev');
  Map<String, Object?> get calendrierCpn => section('calendrier_cpn');
  Map<String, Object?> get calendrierPostnatal => section('calendrier_postnatal');
  Map<String, Object?> get grossesse => section('grossesse');
  Map<String, Object?> get cycle => section('cycle');
  Map<String, Object?> get alimentationEnfant => section('alimentation_enfant');
  Map<String, Object?> get alimentationFemme => section('alimentation_femme');

  /// "Source – version" shown on every advice screen (spec §11).
  String sourceLabel(String sectionName) {
    final source = section(sectionName)['source'] as String?;
    return source == null ? 'v$version' : '${localizedText(source, appLanguage)} – v$version';
  }

  factory ClinicalConfig.fromJson(Map<String, Object?> json) => ClinicalConfig(
    version: json['version']! as int,
    statutValidation: (json['statut_validation'] as String?) ?? 'a_valider',
    libelle: (json['libelle'] as String?) ?? '',
    contenu: (json['contenu']! as Map).cast<String, Object?>(),
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'statut_validation': statutValidation,
    'libelle': libelle,
    'contenu': contenu,
  };

  /// Minimal shape check before a downloaded version replaces the current one,
  /// so a broken file can't silently disable the alerts.
  static List<String> problems(Map<String, Object?> json) {
    final errors = <String>[];
    if (json['version'] is! int) errors.add('version');
    final contenu = json['contenu'];
    if (contenu is! Map) return [...errors, 'contenu'];
    final mal = contenu['malnutrition'];
    if (mal is! Map ||
        (mal['classification'] as Map?)?['regles'] is! List ||
        (mal['orientation'] as Map?)?['regles'] is! List ||
        mal['age_max_mois'] is! num) {
      errors.add('malnutrition');
    }
    final signes = contenu['signes_danger'];
    if (signes is! Map || signes['enfant'] is! List || signes['grossesse'] is! List) {
      errors.add('signes_danger');
    }
    return errors;
  }
}

/// Translations of configuration texts, keyed by the French text
/// (assets/config/translations.json). They fill in the languages the
/// configuration does not carry yet ("en", or `"mg": null`), so a screen never
/// mixes two languages.
final Map<String, Map<String, String>> configTranslations = {};

void loadConfigTranslations(Map<String, Object?> json) {
  configTranslations.clear();
  for (final e in json.entries) {
    final v = e.value;
    if (v is Map) {
      configTranslations[e.key] = {
        for (final t in v.entries)
          if (t.value is String && (t.value as String).isNotEmpty) t.key as String: t.value as String,
      };
    }
  }
}

/// Reads a `{"fr": ..., "mg": ..., "en": ...}` text (or a plain French string)
/// in the user's language. A missing text comes from [configTranslations],
/// and only as a last resort falls back to French.
String localizedText(Object? value, String languageCode) {
  String translate(String fr) => languageCode == 'fr' ? fr : (configTranslations[fr]?[languageCode] ?? fr);
  if (value is String) return translate(value);
  if (value is Map) {
    final text = value[languageCode];
    if (text is String && text.isNotEmpty) return text;
    final fr = value['fr'];
    if (fr is String) return translate(fr);
  }
  return '';
}

num? asNum(Object? value) => value is num ? value : null;
int? asInt(Object? value) => value is num ? value.toInt() : null;

List<Map<String, Object?>> asMapList(Object? value) => value is List
    ? value.whereType<Map<Object?, Object?>>().map((m) => m.cast<String, Object?>()).toList()
    : const [];
