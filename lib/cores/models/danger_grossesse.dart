import 'model.dart';

class DangerGrossesse extends SyncableModel {
  const DangerGrossesse({
    super.id,
    this.idGrossesse,
    this.typeDangerGrossesseId,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory DangerGrossesse.fromMap(Map<String, Object?> map) => DangerGrossesse(
    id: map['id'] as int?,
    idGrossesse: map['id_grossesse'] as int?,
    typeDangerGrossesseId: map['Type_danger_Grossesse_id'] as int?,
    version: map['version'] as int? ?? 1,
    updatedAt: map['updated_at'] as String?,
    deviceId: map['device_id'] as String?,
    deletedAt: map['deleted_at'] as String?,
    syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
  );

  static const String table = 'Danger_Grossesse';

  final int? idGrossesse;
  final int? typeDangerGrossesseId;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'id_grossesse': idGrossesse,
    'Type_danger_Grossesse_id': typeDangerGrossesseId,
    ...syncColumns,
  };
}
