import 'model.dart';

class Grossesse extends SyncableModel {
  const Grossesse({
    super.id,
    this.ddr,
    this.dpa,
    this.userId,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory Grossesse.fromMap(Map<String, Object?> map) => Grossesse(
    id: map['id'] as int?,
    ddr: map['DDR'] as String?,
    dpa: map['DpA'] as String?,
    userId: map['User_id'] as int?,
    version: map['version'] as int? ?? 1,
    updatedAt: map['updated_at'] as String?,
    deviceId: map['device_id'] as String?,
    deletedAt: map['deleted_at'] as String?,
    syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
  );

  static const String table = 'Grossesse';

  final String? ddr;
  final String? dpa;
  final int? userId;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'DDR': ddr,
    'DpA': dpa,
    'User_id': userId,
    ...syncColumns,
  };
}
