import 'model.dart';

class Referencement extends SyncableModel {
  const Referencement({
    super.id,
    this.codeUnique,
    this.origine,
    this.idEnfant,
    this.idGrossesse,
    this.idMesure,
    this.ascId,
    this.csbId,
    this.priorite,
    this.motif,
    this.status,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory Referencement.fromMap(Map<String, Object?> map) => Referencement(
    id: map['id'] as int?,
    codeUnique: map['code_Unique'] as String?,
    origine: map['origine'] as String?,
    idEnfant: map['id_enfant'] as int?,
    idGrossesse: map['id_grossesse'] as int?,
    idMesure: map['id_mesure'] as int?,
    ascId: map['asc_id'] as String?,
    csbId: map['csb_id'] as int?,
    priorite: map['priorite'] as String?,
    motif: map['motif'] as String?,
    status: map['status'] as String?,
    version: map['version'] as int? ?? 1,
    updatedAt: map['updated_at'] as String?,
    deviceId: map['device_id'] as String?,
    deletedAt: map['deleted_at'] as String?,
    syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
  );

  static const String table = 'referencement';

  final String? codeUnique;
  final String? origine;
  final int? idEnfant;
  final int? idGrossesse;
  final int? idMesure;
  final String? ascId;
  final int? csbId;
  final String? priorite;
  final String? motif;
  final String? status;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'code_Unique': codeUnique,
    'origine': origine,
    'id_enfant': idEnfant,
    'id_grossesse': idGrossesse,
    'id_mesure': idMesure,
    'asc_id': ascId,
    'csb_id': csbId,
    'priorite': priorite,
    'motif': motif,
    'status': status,
    ...syncColumns,
  };
}
