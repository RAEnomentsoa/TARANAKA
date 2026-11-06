import 'model.dart';

class Cycle extends SyncableModel {
  const Cycle({
    super.id,
    this.dateDebut,
    this.dateFin,
    this.intensite,
    this.dureCycle,
    this.dureRegle,
    this.symptome,
    this.estimationProchain,
    this.userId,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory Cycle.fromMap(Map<String, Object?> map) => Cycle(
    id: map['id'] as int?,
    dateDebut: map['date_debut'] as String?,
    dateFin: map['date_fin'] as String?,
    intensite: map['intensite'] as String?,
    dureCycle: map['dure_cycle'] as int?,
    dureRegle: map['dure_regle'] as int?,
    symptome: map['symptome'] as String?,
    estimationProchain: map['estimationProchain'] as String?,
    userId: map['User_id'] as int?,
    version: map['version'] as int? ?? 1,
    updatedAt: map['updated_at'] as String?,
    deviceId: map['device_id'] as String?,
    deletedAt: map['deleted_at'] as String?,
    syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
  );

  static const String table = 'Cycle';

  final String? dateDebut;
  final String? dateFin;
  final String? intensite;
  final int? dureCycle;
  final int? dureRegle;
  final String? symptome;
  final String? estimationProchain;
  final int? userId;

  Cycle withUser(int? userId) => Cycle(
    id: id,
    dateDebut: dateDebut,
    dateFin: dateFin,
    intensite: intensite,
    dureCycle: dureCycle,
    dureRegle: dureRegle,
    symptome: symptome,
    estimationProchain: estimationProchain,
    userId: userId,
    version: version,
    updatedAt: updatedAt,
    deviceId: deviceId,
    deletedAt: deletedAt,
    syncStatus: syncStatus,
  );

  /// Copie portant ces valeurs calculées, y compris `null`.
  Cycle withComputed({
    required int? dureCycle,
    required int? dureRegle,
    required String? estimationProchain,
  }) => Cycle(
    id: id,
    dateDebut: dateDebut,
    dateFin: dateFin,
    intensite: intensite,
    dureCycle: dureCycle,
    dureRegle: dureRegle,
    symptome: symptome,
    estimationProchain: estimationProchain,
    userId: userId,
    version: version,
    updatedAt: updatedAt,
    deviceId: deviceId,
    deletedAt: deletedAt,
    syncStatus: syncStatus,
  );

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'date_debut': dateDebut,
    'date_fin': dateFin,
    'intensite': intensite,
    'dure_cycle': dureCycle,
    'dure_regle': dureRegle,
    'symptome': symptome,
    'estimationProchain': estimationProchain,
    'User_id': userId,
    ...syncColumns,
  };
}
