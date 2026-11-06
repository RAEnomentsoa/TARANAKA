/// Valeurs de la colonne `sync_status`.
abstract final class SyncStatus {
  static const String pending = 'pending';
}

/// Ligne d'une table. Les dates sont des chaînes ISO 8601, comme en base.
abstract class Model {
  const Model({this.id});

  final int? id;

  Map<String, Object?> toMap();
}

/// Ligne d'une table portant les colonnes de synchronisation.
///
/// Ces colonnes sont renseignées par `SyncableRepository`.
abstract class SyncableModel extends Model {
  const SyncableModel({
    super.id,
    this.version = 1,
    this.updatedAt,
    this.deviceId,
    this.deletedAt,
    this.syncStatus = SyncStatus.pending,
  });

  final int version;
  final String? updatedAt;
  final String? deviceId;
  final String? deletedAt;
  final String syncStatus;

  Map<String, Object?> get syncColumns => {
    'version': version,
    'updated_at': updatedAt,
    'device_id': deviceId,
    'deleted_at': deletedAt,
    'sync_status': syncStatus,
  };
}
