import 'dart:convert';

import 'sync_engine.dart';

// Conversions between the local columns (SQLite: 0/1, JSON text, REAL) and
// the server fields (docs/openapi.yaml: booleans, lists, decimal strings).

double? _dec(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
int _bool(Object? v) => v == true ? 1 : 0;
int? _boolOrNull(Object? v) => v == null ? null : _bool(v);
bool? _toBool(Object? v) => v == null ? null : v == 1 || v == true;
String? _str(Object? v) => v?.toString();
String? _fixed(Object? v, int digits) => v is num ? v.toStringAsFixed(digits) : null;
String _jsonList(Object? v) => jsonEncode(v is List ? v : const []);
List<Object?> _list(Object? v) {
  if (v is List) return v;
  if (v is String && v.isNotEmpty) {
    final decoded = jsonDecode(v);
    if (decoded is List) return decoded;
  }
  return const [];
}

Map<String, Object?> _sync(Map<String, Object?> r) => {
  'id': r['id'],
  'version': r['version'] ?? 1,
  'updated_at': r['updated_at'],
};

/// What a payload needs that is not in the row itself.
class PayloadContext {
  const PayloadContext({this.foodGroups});

  /// Server columns `g1_lait_maternel` … `g8_autres_fruits_legumes` for the
  /// foods of a day (the phone knows the group of each food).
  final Map<String, bool> Function(Set<String> foods, String breastfeeding)? foodGroups;
}

/// One synced table: how a server row becomes a local row, and back.
class SyncTable {
  const SyncTable({
    required this.name,
    required this.toLocal,
    required this.toServer,
    this.naturalKey = const [],
    this.cycle = false,
    this.clinical = true,
  });

  /// Same name on the phone and on the server (`/api/sync/`).
  final String name;
  final Map<String, Object?> Function(Map<String, Object?> server) toLocal;

  /// Local row → `donnees` of a push operation.
  final Map<String, Object?> Function(Map<String, Object?> row, PayloadContext ctx) toServer;

  /// "One row per day / dose" (local unique key besides `id`).
  final List<String> naturalKey;

  /// Menstrual data: only sent when the woman shares her cycle (D16 a).
  final bool cycle;

  /// Clinical data: a conflict goes to a person on the web. Otherwise (personal
  /// data) the phone decides.
  final bool clinical;

  TableAdapter get adapter =>
      TableAdapter(serverTable: name, localTable: name, toLocal: toLocal, naturalKey: naturalKey);
}

abstract final class SyncTables {
  static final cycle = SyncTable(
    name: 'cycle',
    cycle: true,
    clinical: false,
    toLocal: (r) => {
      ..._sync(r),
      'date_debut': r['date_debut'],
      'date_fin': r['date_fin'],
      'intensite': r['intensite'] ?? 'moyenne',
      'douleur': r['douleur'] ?? 0,
      'humeur': r['humeur'],
      'notes': r['notes'] ?? '',
      'symptomes': _jsonList(r['symptomes']),
      'irreguliere': _bool(r['irreguliere']),
    },
    toServer: (r, _) => {
      'date_debut': r['date_debut'],
      'date_fin': r['date_fin'],
      'intensite': r['intensite'],
      'douleur': r['douleur'],
      'humeur': r['humeur'],
      'notes': r['notes'] ?? '',
      'symptomes': _list(r['symptomes']),
      'irreguliere': r['irreguliere'] == 1,
    },
  );

  static final cycleDay = SyncTable(
    name: 'cycle_jour',
    cycle: true,
    clinical: false,
    naturalKey: const ['date_jour'],
    toLocal: (r) => {
      ..._sync(r),
      'date_jour': r['date_jour'],
      'flux': _blankToNull(r['flux']),
      'douleur': r['douleur'],
      'humeur': r['humeur'],
      'symptomes': _jsonList(r['symptomes']),
    },
    toServer: (r, _) => {
      'date_jour': r['date_jour'],
      'flux': r['flux'] ?? '',
      'douleur': r['douleur'],
      'humeur': r['humeur'],
      'symptomes': _list(r['symptomes']),
    },
  );

  /// Women's food groups: numbers on the phone, codes (strings) on the server.
  static final womenDiet = SyncTable(
    name: 'alimentation_femme',
    clinical: false,
    naturalKey: const ['date_jour'],
    toLocal: (r) => {
      ..._sync(r),
      'date_jour': r['date_jour'],
      'groupes': jsonEncode([for (final g in _list(r['groupes'])) ?int.tryParse('$g')]..sort()),
    },
    toServer: (r, _) => {
      'date_jour': r['date_jour'],
      'groupes': [for (final g in _list(r['groupes'])) '$g'],
    },
  );

  static final pregnancy = SyncTable(
    name: 'grossesse',
    toLocal: (r) => {
      ..._sync(r),
      'user_id': r['user_id'],
      'ddr': r['ddr'],
      'dpa': r['dpa'],
      'dpa_saisie': r['dpa_saisie'],
      'terme_confirme_date': r['terme_confirme_date'],
      'terme_confirme_jours': r['terme_confirme_jours'],
      'date_accouchement': r['date_accouchement'],
      'mode_allaitement': _blankToNull(r['mode_allaitement']),
      'terminee': _bool(r['terminee']),
    },
    toServer: (r, _) => {
      if (r['user_id'] != null) 'user_id': r['user_id'],
      'ddr': r['ddr'],
      'dpa': r['dpa'],
      'dpa_saisie': r['dpa_saisie'],
      'terme_confirme_date': r['terme_confirme_date'],
      'terme_confirme_jours': r['terme_confirme_jours'],
      'date_accouchement': r['date_accouchement'],
      'mode_allaitement': r['mode_allaitement'] ?? '',
      'terminee': r['terminee'] == 1,
    },
  );

  /// The server finds the type of the sign from its config `code` (D16).
  static final danger = SyncTable(
    name: 'danger_grossesse',
    toLocal: (r) => {
      ..._sync(r),
      'grossesse_id': r['grossesse_id'],
      'code': r['code'] ?? '',
      'periode': r['periode'] ?? '',
      'date_signalement': r['date_signalement'],
    },
    toServer: (r, _) => {
      'grossesse_id': r['grossesse_id'],
      'code': r['code'],
      'periode': r['periode'],
      'date_signalement': r['date_signalement'],
    },
  );

  static final careContact = SyncTable(
    name: 'contact_soin',
    naturalKey: const ['grossesse_id', 'type', 'numero'],
    toLocal: (r) => {
      ..._sync(r),
      'grossesse_id': r['grossesse_id'],
      'type': r['type'],
      'numero': r['numero'],
      'date_faite': r['date_faite'],
    },
    toServer: (r, _) => {
      'grossesse_id': r['grossesse_id'],
      'type': r['type'],
      'numero': r['numero'],
      'date_faite': r['date_faite'],
    },
  );

  static final pregnancyCheck = SyncTable(
    name: 'suivi_grossesse',
    toLocal: (r) => {
      ..._sync(r),
      'grossesse_id': r['grossesse_id'],
      'date_jour': r['date_jour'],
      'poids_kg': _dec(r['poids_kg']),
      'tension_sys': r['tension_sys'],
      'tension_dia': r['tension_dia'],
      'hauteur_uterine_cm': _dec(r['hauteur_uterine_cm']),
      'hemoglobine_g_dl': _dec(r['hemoglobine_g_dl']),
      'glycemie_g_l': _dec(r['glycemie_g_l']),
      'glycemie_a_jeun': _boolOrNull(r['glycemie_a_jeun']),
      'temperature_c': _dec(r['temperature_c']),
      'source': r['source'] ?? 'domicile',
      'notes': r['notes'] ?? '',
    },
    toServer: (r, _) => {
      'grossesse_id': r['grossesse_id'],
      'date_jour': r['date_jour'],
      'poids_kg': _fixed(r['poids_kg'], 2),
      'tension_sys': r['tension_sys'],
      'tension_dia': r['tension_dia'],
      'hauteur_uterine_cm': _fixed(r['hauteur_uterine_cm'], 1),
      'hemoglobine_g_dl': _fixed(r['hemoglobine_g_dl'], 1),
      'glycemie_g_l': _fixed(r['glycemie_g_l'], 2),
      'glycemie_a_jeun': _toBool(r['glycemie_a_jeun']),
      'temperature_c': _fixed(r['temperature_c'], 1),
      'source': r['source'] ?? 'domicile',
      'notes': r['notes'] ?? '',
    },
  );

  static final babyMovements = SyncTable(
    name: 'mouvement_bebe',
    clinical: false,
    naturalKey: const ['grossesse_id', 'date_jour'],
    toLocal: (r) => {
      ..._sync(r),
      'grossesse_id': r['grossesse_id'],
      'date_jour': r['date_jour'],
      'mouvements': r['mouvements'],
    },
    toServer: (r, _) => {
      'grossesse_id': r['grossesse_id'],
      'date_jour': r['date_jour'],
      'mouvements': r['mouvements'],
    },
  );

  static final babyMovementEvent = SyncTable(
    name: 'mouvement_evenement',
    clinical: false,
    toLocal: (r) => {
      ..._sync(r),
      'grossesse_id': r['grossesse_id'],
      'horodatage': _localTime(r['horodatage']),
      'type': r['type'],
    },
    toServer: (r, _) => {'grossesse_id': r['grossesse_id'], 'horodatage': r['horodatage'], 'type': r['type']},
  );

  static final child = SyncTable(
    name: 'enfant',
    toLocal: (r) => {
      ..._sync(r),
      'nom': r['nom'],
      'sexe': r['sexe'],
      'date_naissance': r['date_naissance'],
      'region_id': r['region_id'],
      'asc_id': r['asc_id'],
      'mere_id': r['mere_id'],
      'grossesse_id': r['grossesse_id'],
      'poids_naissance_kg': _dec(r['poids_naissance_kg']),
      'statut_prise_en_charge': r['statut_prise_en_charge'] ?? 'aucun',
    },
    toServer: (r, _) => {
      'nom': r['nom'],
      'sexe': r['sexe'],
      'date_naissance': r['date_naissance'],
      'poids_naissance_kg': _fixed(r['poids_naissance_kg'], 2),
      if (r['region_id'] != null) 'region_id': r['region_id'],
      if (r['mere_id'] != null) 'mere_id': r['mere_id'],
      if (r['grossesse_id'] != null) 'grossesse_id': r['grossesse_id'],
    },
  );

  static final measurement = SyncTable(
    name: 'mesure',
    toLocal: (r) => {
      ..._sync(r),
      'enfant_id': r['enfant_id'],
      'date_mesure': r['date_mesure'],
      'poids_kg': _dec(r['poids_kg']),
      'taille_cm': _dec(r['taille_cm']),
      'position': r['position'],
      'pb_mm': r['pb_mm'],
      'oedemes_bilateraux': r['oedemes_bilateraux'] ?? 'aucun',
      'signes_danger': _jsonList(r['signes_danger']),
      'complications_medicales': _bool(r['complications_medicales']),
      'appetit': r['appetit'] ?? 'non_teste',
      'difficultes_allaitement': _bool(r['difficultes_allaitement']),
      'age_jour': r['age_jour'],
      'age_mois': r['age_mois'],
      'taille_corrigee_cm': _dec(r['taille_corrigee_cm']),
      'waz': _dec(r['waz']),
      'haz': _dec(r['haz']),
      'whz': _dec(r['whz']),
      'flag_aberrant': _bool(r['flag_aberrant']),
      'classification': r['classification'],
      'orientation_centre': r['orientation_centre'],
      'urgence': r['urgence'],
      'date_prochain_controle': r['date_prochain_controle'],
      'config_version': r['config_version'],
      'alerte': r['alerte'] ?? 'vert',
      'motif_alerte': r['motif_alerte'] ?? '',
    },
    toServer: (r, _) => {
      'enfant_id': r['enfant_id'],
      'date_mesure': r['date_mesure'],
      'poids_kg': _fixed(r['poids_kg'], 2),
      'taille_cm': _fixed(r['taille_cm'], 1),
      'position': r['position'],
      'pb_mm': r['pb_mm'],
      'oedemes_bilateraux': r['oedemes_bilateraux'] ?? 'aucun',
      'waz': _fixed(r['waz'], 2),
      'haz': _fixed(r['haz'], 2),
      'whz': _fixed(r['whz'], 2),
      'flag_aberrant': r['flag_aberrant'] == 1,
      'alerte': r['alerte'] ?? 'vert',
      'motif_alerte': r['motif_alerte'] ?? '',
      'signes_danger': _list(r['signes_danger']),
      'complications_medicales': r['complications_medicales'] == 1,
      'appetit': r['appetit'] ?? 'non_teste',
      'difficultes_allaitement': r['difficultes_allaitement'] == 1,
    },
  );

  /// The feeding log, with the 8 groups g1 … g8 worked out on the phone.
  static final feedingLog = SyncTable(
    name: 'journal_alimentaire',
    clinical: false,
    naturalKey: const ['enfant_id', 'date_jour'],
    toLocal: (r) => {
      ..._sync(r),
      'enfant_id': r['enfant_id'],
      'date_jour': r['date_jour'],
      'type_allaitement': r['type_allaitement'] ?? 'aucun',
      'aliments': _jsonList(r['aliments']),
      'repas': r['repas'] ?? 0,
      'laits': r['laits'] ?? 0,
      'tetees': r['tetees'],
      'autres_recus': _jsonList(r['autres_recus']),
    },
    toServer: (r, ctx) {
      final foods = _list(r['aliments']).whereType<String>().toSet();
      final breastfeeding = (r['type_allaitement'] as String?) ?? 'aucun';
      return {
        'enfant_id': r['enfant_id'],
        'date_jour': r['date_jour'],
        'type_allaitement': breastfeeding,
        'aliments': foods.toList()..sort(),
        'repas': r['repas'] ?? 0,
        'laits': r['laits'] ?? 0,
        'tetees': r['tetees'],
        'autres_recus': _list(r['autres_recus']),
        ...?ctx.foodGroups?.call(foods, breastfeeding),
      };
    },
  );

  static final vaccine = SyncTable(
    name: 'vaccin_fait',
    naturalKey: const ['enfant_id', 'code'],
    toLocal: (r) => {
      ..._sync(r),
      'enfant_id': r['enfant_id'],
      'code': r['code'],
      'date_faite': r['date_faite'],
      'centre': r['centre'] ?? '',
      'professionnel': r['professionnel'] ?? '',
      'confirme_carnet': _boolOrNull(r['confirme_carnet']),
    },
    toServer: (r, _) => {
      'enfant_id': r['enfant_id'],
      'code': r['code'],
      'date_faite': r['date_faite'],
      'centre': r['centre'] ?? '',
      'professionnel': r['professionnel'] ?? '',
      'confirme_carnet': _toBool(r['confirme_carnet']),
    },
  );

  static final feed = SyncTable(
    name: 'tetee',
    clinical: false,
    toLocal: (r) => {
      ..._sync(r),
      'enfant_id': r['enfant_id'],
      'horodatage': _localTime(r['horodatage']),
      'type': r['type'],
      'duree_min': r['duree_min'],
      'quantite_ml': r['quantite_ml'],
    },
    toServer: (r, _) => {
      'enfant_id': r['enfant_id'],
      'horodatage': r['horodatage'],
      'type': r['type'],
      'duree_min': r['duree_min'],
      'quantite_ml': r['quantite_ml'],
    },
  );

  static final referral = SyncTable(
    name: 'referencement',
    toLocal: (r) => {
      ..._sync(r),
      'code_unique': r['code_unique'],
      'origine': r['origine'],
      'enfant_id': r['enfant_id'],
      'grossesse_id': r['grossesse_id'],
      'mesure_id': r['mesure_id'],
      'csb_id': r['csb_id'],
      'priorite': r['priorite'],
      'urgence': r['urgence'],
      'motif': r['motif'],
      'date_referencement': r['date_referencement'],
      'status': r['status'],
      'date_reception': _str(r['date_reception']),
      'date_prise_en_charge': _str(r['date_prise_en_charge']),
      'date_suivi': _str(r['date_suivi']),
      'date_sortie': _str(r['date_sortie']),
      'issue_sortie': r['issue_sortie'],
      // The server has it: "Non transmise" no longer applies.
      'transmis': 1,
    },
    toServer: (r, _) => const {},
  );

  static final appointment = SyncTable(
    name: 'rendez_vous',
    toLocal: (r) => {
      ..._sync(r),
      'enfant_id': r['enfant_id'],
      'referencement_id': r['referencement_id'],
      'csb_id': r['csb_id'],
      'date_prevue': r['date_prevue'],
      'type_rendez_vous': r['type_rendez_vous'],
      'statut': r['statut'],
      'motif': r['motif'],
    },
    toServer: (r, _) => const {},
  );

  /// Tables of the personal mode, parents first (a first push sends the
  /// pregnancy before its contacts, the child before its measurements).
  static final List<SyncTable> personalWritable = [
    cycle,
    cycleDay,
    womenDiet,
    pregnancy,
    danger,
    careContact,
    pregnancyCheck,
    babyMovements,
    babyMovementEvent,
    child,
    measurement,
    feedingLog,
    vaccine,
    feed,
  ];

  /// What the woman's phone pulls: her own rows, and what the health centre
  /// updates (referral status, appointments).
  static final List<SyncTable> personalPull = [...personalWritable, referral, appointment];

  /// What the agent's phone pulls: the clinical file of the women it follows
  /// (D16). Cycle, diet and movements are only in the file read online.
  static final List<SyncTable> agentPull = [
    pregnancy,
    danger,
    careContact,
    pregnancyCheck,
    child,
    measurement,
    feedingLog,
    vaccine,
    referral,
    appointment,
  ];

  static SyncTable? byName(String name) {
    for (final t in personalPull) {
      if (t.name == name) return t;
    }
    return null;
  }
}

Object? _blankToNull(Object? v) => v is String && v.isEmpty ? null : v;

/// The server answers with a zoned date-time; the phone keeps local time
/// without zone (the feeds and movements of a day stay on that day).
Object? _localTime(Object? v) {
  if (v is! String) return v;
  final parsed = DateTime.tryParse(v);
  if (parsed == null) return v;
  final l = parsed.toLocal();
  return DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second).toIso8601String();
}
