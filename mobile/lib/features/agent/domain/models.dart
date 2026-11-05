import 'dart:convert';

import '../../../core/sync/sync_status.dart';
import '../../../core/util/clock.dart';

class Child {
  const Child({
    required this.id,
    required this.name,
    required this.sex,
    required this.birthDate,
    required this.regionId,
    required this.careStatus,
    required this.version,
    required this.syncStatus,
  });

  final String id;
  final String name;
  final String sex;
  final DateTime birthDate;
  final int? regionId;
  final String careStatus;
  final int version;
  final SyncStatus syncStatus;

  static Child fromRow(Map<String, Object?> r) => Child(
    id: r['id']! as String,
    name: r['nom']! as String,
    sex: r['sexe']! as String,
    birthDate: parseIsoDate(r['date_naissance']! as String),
    regionId: r['region_id'] as int?,
    careStatus: r['statut_prise_en_charge']! as String,
    version: r['version']! as int,
    syncStatus: SyncStatus.parse(r['sync_status']),
  );
}

class Measurement {
  const Measurement({
    required this.id,
    required this.childId,
    required this.date,
    required this.weightKg,
    required this.lengthCm,
    required this.position,
    required this.muacMm,
    required this.oedema,
    required this.dangerSigns,
    required this.complications,
    required this.appetite,
    required this.ageMonths,
    required this.waz,
    required this.haz,
    required this.whz,
    required this.flagged,
    required this.classification,
    required this.centre,
    required this.urgence,
    required this.nextCheck,
    required this.configVersion,
    required this.syncStatus,
  });

  final String id;
  final String childId;
  final DateTime date;
  final double weightKg;
  final double lengthCm;
  final String position;
  final int? muacMm;
  final String oedema;
  final List<String> dangerSigns;
  final bool complications;
  final String appetite;
  final int? ageMonths;
  final double? waz;
  final double? haz;
  final double? whz;
  final bool flagged;
  final String? classification;
  final String? centre;
  final String? urgence;
  final DateTime? nextCheck;
  final int? configVersion;
  final SyncStatus syncStatus;

  static Measurement fromRow(Map<String, Object?> r) => Measurement(
    id: r['id']! as String,
    childId: r['enfant_id']! as String,
    date: parseIsoDate(r['date_mesure']! as String),
    weightKg: (r['poids_kg']! as num).toDouble(),
    lengthCm: (r['taille_cm']! as num).toDouble(),
    position: r['position']! as String,
    muacMm: r['pb_mm'] as int?,
    oedema: r['oedemes_bilateraux']! as String,
    dangerSigns: (jsonDecode(r['signes_danger']! as String) as List).cast<String>(),
    complications: r['complications_medicales'] == 1,
    appetite: r['appetit']! as String,
    ageMonths: r['age_mois'] as int?,
    waz: (r['waz'] as num?)?.toDouble(),
    haz: (r['haz'] as num?)?.toDouble(),
    whz: (r['whz'] as num?)?.toDouble(),
    flagged: r['flag_aberrant'] == 1,
    classification: _blank(r['classification']),
    centre: _blank(r['orientation_centre']),
    urgence: _blank(r['urgence']),
    nextCheck: _blank(r['date_prochain_controle']) == null
        ? null
        : parseIsoDate(r['date_prochain_controle']! as String),
    configVersion: r['config_version'] as int?,
    syncStatus: SyncStatus.parse(r['sync_status']),
  );
}

/// Referral lifecycle (spec §7): envoye (Référé) → recu → pris_en_charge
/// → en_suivi → sortie.
class Referral {
  const Referral({
    required this.id,
    required this.code,
    required this.childId,
    required this.measurementId,
    required this.centreId,
    required this.priorite,
    required this.urgence,
    required this.motif,
    required this.referredAt,
    required this.status,
    required this.receivedAt,
    required this.exitOutcome,
    required this.transmitted,
    required this.previousCode,
    required this.syncStatus,
  });

  final String id;
  final String code;
  final String? childId;
  final String? measurementId;
  final int? centreId;
  final String priorite;
  final String? urgence;
  final String motif;
  final DateTime referredAt;
  final String status;
  final DateTime? receivedAt;
  final String? exitOutcome;

  /// Acknowledged by the server ("Non transmise" until then).
  final bool transmitted;
  final String? previousCode;
  final SyncStatus syncStatus;

  static Referral fromRow(Map<String, Object?> r) => Referral(
    id: r['id']! as String,
    code: r['code_unique']! as String,
    childId: r['enfant_id'] as String?,
    measurementId: r['mesure_id'] as String?,
    centreId: r['csb_id'] as int?,
    priorite: r['priorite']! as String,
    urgence: _blank(r['urgence']),
    motif: r['motif']! as String,
    referredAt: DateTime.parse(r['date_referencement']! as String),
    status: r['status']! as String,
    receivedAt: _blank(r['date_reception']) == null ? null : DateTime.parse(r['date_reception']! as String),
    exitOutcome: _blank(r['issue_sortie']),
    transmitted: r['transmis'] == 1,
    previousCode: r['ancien_code'] as String?,
    syncStatus: SyncStatus.parse(r['sync_status']),
  );
}

class Centre {
  const Centre({required this.id, required this.name, required this.type, this.regionId, this.tel});

  final int id;
  final String name;

  /// csb | crenam | crenas | creni
  final String type;
  final int? regionId;
  final String? tel;

  static Centre fromRow(Map<String, Object?> r) => Centre(
    id: r['id']! as int,
    name: r['name']! as String,
    type: r['type_centre']! as String,
    regionId: r['region_id'] as int?,
    tel: r['tel'] as String?,
  );
}

class Appointment {
  const Appointment({required this.id, this.childId, required this.date, this.status, this.reason});

  final String id;
  final String? childId;
  final DateTime date;
  final String? status;
  final String? reason;
}

String? _blank(Object? v) => v is String && v.isNotEmpty ? v : null;
