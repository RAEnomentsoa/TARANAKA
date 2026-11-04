import 'dart:convert';

import '../../../core/sync/outbox.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/referral_code.dart';

double? _dec(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
int _bool(Object? v) => v == true ? 1 : 0;
String? _str(Object? v) => v?.toString();

/// Tables the agent mode syncs, parents first.
List<TableAdapter> agentAdapters() => [
  TableAdapter(
    serverTable: 'enfant',
    localTable: 'enfant',
    toLocal: (r) => {
      'id': r['id'],
      'nom': r['nom'],
      'sexe': r['sexe'],
      'date_naissance': r['date_naissance'],
      'region_id': r['region_id'],
      'asc_id': r['asc_id'],
      'mere_id': r['mere_id'],
      'grossesse_id': r['grossesse_id'],
      'statut_prise_en_charge': r['statut_prise_en_charge'] ?? 'aucun',
      'version': r['version'] ?? 1,
      'updated_at': r['updated_at'],
    },
  ),
  TableAdapter(
    serverTable: 'mesure',
    localTable: 'mesure',
    toLocal: (r) => {
      'id': r['id'],
      'enfant_id': r['enfant_id'],
      'date_mesure': r['date_mesure'],
      'poids_kg': _dec(r['poids_kg']),
      'taille_cm': _dec(r['taille_cm']),
      'position': r['position'],
      'pb_mm': r['pb_mm'],
      'oedemes_bilateraux': r['oedemes_bilateraux'] ?? 'aucun',
      'signes_danger': jsonEncode(r['signes_danger'] ?? const []),
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
      'version': r['version'] ?? 1,
      'updated_at': r['updated_at'],
    },
  ),
  TableAdapter(
    serverTable: 'referencement',
    localTable: 'referencement',
    toLocal: (r) => {
      'id': r['id'],
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
      'version': r['version'] ?? 1,
      'updated_at': r['updated_at'],
    },
  ),
  TableAdapter(
    serverTable: 'rendez_vous',
    localTable: 'rendez_vous',
    toLocal: (r) => {
      'id': r['id'],
      'enfant_id': r['enfant_id'],
      'referencement_id': r['referencement_id'],
      'csb_id': r['csb_id'],
      'date_prevue': r['date_prevue'],
      'type_rendez_vous': r['type_rendez_vous'],
      'statut': r['statut'],
      'motif': r['motif'],
      'version': r['version'] ?? 1,
      'updated_at': r['updated_at'],
    },
  ),
];

/// The server refuses a referral code already used by another phone: draw a
/// new install prefix, give the referral a new code (the old one is kept to
/// be shown), and retry.
ErrorFixer referralCodeFixer(ReferralCodeGenerator codes) => (db, op, errors) async {
  if (op.operation != 'create' || errors is! Map || !errors.containsKey('code_unique')) {
    return false;
  }
  await codes.rotatePrefix();
  final code = await codes.next();
  await db.rawUpdate(
    'UPDATE referencement SET ancien_code = coalesce(ancien_code, code_unique), code_unique = ? WHERE id = ?',
    [code, op.rowId],
  );
  await Outbox.replacePayloadField(db, op.seq, 'code_unique', code);
  return true;
};
