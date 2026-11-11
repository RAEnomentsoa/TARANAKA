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
    this.motherId,
    this.pregnancyId,
  });

  final String id;
  final String name;
  final String sex;
  final DateTime birthDate;
  final int? regionId;
  final String careStatus;
  final int version;
  final SyncStatus syncStatus;

  /// The beneficiary (D16): no child without a mother any more.
  final String? motherId;
  final String? pregnancyId;

  static Child fromRow(Map<String, Object?> r) => Child(
    id: r['id']! as String,
    name: r['nom']! as String,
    sex: r['sexe']! as String,
    birthDate: parseIsoDate(r['date_naissance']! as String),
    regionId: r['region_id'] as int?,
    careStatus: r['statut_prise_en_charge']! as String,
    version: r['version']! as int,
    syncStatus: SyncStatus.parse(r['sync_status']),
    motherId: r['mere_id'] as String?,
    pregnancyId: r['grossesse_id'] as String?,
  );
}

/// A woman of the agent's zone (`/api/beneficiaries/`), and her file once
/// opened (D16).
class Beneficiary {
  const Beneficiary({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.identifiant,
    this.phone,
    this.regionId,
    this.code,
    this.followed = false,
    this.pregnant = false,
    this.childCount = 0,
    this.sharesCycle = false,
    this.file,
    this.fileAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? identifiant;
  final String? phone;
  final int? regionId;

  /// `code_beneficiaire`, shown by her (QR or typed).
  final String? code;
  final bool followed;
  final bool pregnant;
  final int childCount;
  final bool sharesCycle;

  /// Her whole file as last downloaded (`/api/beneficiaries/{id}/`).
  final Map<String, Object?>? file;
  final DateTime? fileAt;

  String get displayName => '$firstName $lastName'.trim();

  static Beneficiary fromRow(Map<String, Object?> r) => Beneficiary(
    id: r['id']! as String,
    firstName: (r['prenom'] as String?) ?? '',
    lastName: (r['nom'] as String?) ?? '',
    identifiant: r['identifiant'] as String?,
    phone: r['phone'] as String?,
    regionId: r['region_id'] as int?,
    code: r['code_beneficiaire'] as String?,
    followed: r['suivie'] == 1,
    pregnant: r['grossesse_en_cours'] == 1,
    childCount: (r['nb_enfants'] as int?) ?? 0,
    sharesCycle: r['partage_cycle'] == 1,
    file: r['dossier'] is String
        ? (jsonDecode(r['dossier']! as String) as Map).cast<String, Object?>()
        : null,
    fileAt: r['dossier_at'] is String ? DateTime.tryParse(r['dossier_at']! as String) : null,
  );
}

/// A pregnancy of a followed woman, as the agent sees it.
class AgentPregnancy {
  const AgentPregnancy({
    required this.id,
    required this.userId,
    this.lmp,
    this.dueDate,
    this.deliveredOn,
    this.ended = false,
    required this.syncStatus,
  });

  final String id;
  final String? userId;
  final DateTime? lmp;
  final DateTime? dueDate;
  final DateTime? deliveredOn;
  final bool ended;
  final SyncStatus syncStatus;

  bool get ongoing => !ended && deliveredOn == null;

  static AgentPregnancy fromRow(Map<String, Object?> r) => AgentPregnancy(
    id: r['id']! as String,
    userId: r['user_id'] as String?,
    lmp: _blank(r['ddr']) == null ? null : parseIsoDate(r['ddr']! as String),
    dueDate: _blank(r['dpa']) == null ? null : parseIsoDate(r['dpa']! as String),
    deliveredOn: _blank(r['date_accouchement']) == null
        ? null
        : parseIsoDate(r['date_accouchement']! as String),
    ended: r['terminee'] == 1,
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
    this.origin = 'enfant',
    this.pregnancyId,
  });

  /// `enfant` or `grossesse` (a pregnant woman referred for danger signs).
  final String origin;
  final String? pregnancyId;

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
    origin: (r['origine'] as String?) ?? 'enfant',
    pregnancyId: r['grossesse_id'] as String?,
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
