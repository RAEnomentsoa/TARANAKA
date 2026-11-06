import 'model.dart';

class JournalAlimentaire extends SyncableModel {
  const JournalAlimentaire({
    super.id,
    this.enfantId,
    this.dateJour,
    this.typeAllaitement,
    this.g1ToG8,
    this.scoreDiversite,
    this.notes,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory JournalAlimentaire.fromMap(Map<String, Object?> map) =>
      JournalAlimentaire(
        id: map['id'] as int?,
        enfantId: map['enfant_id'] as int?,
        dateJour: map['date_jour'] as String?,
        typeAllaitement: map['type_allaitement'] as String?,
        g1ToG8: map['g1_to_g8'] as String?,
        scoreDiversite: map['score_diversite'] as int?,
        notes: map['notes'] as String?,
        version: map['version'] as int? ?? 1,
        updatedAt: map['updated_at'] as String?,
        deviceId: map['device_id'] as String?,
        deletedAt: map['deleted_at'] as String?,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  static const String table = 'journal_alimentaire';

  final int? enfantId;
  final String? dateJour;
  final String? typeAllaitement;
  final String? g1ToG8;
  final int? scoreDiversite;
  final String? notes;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'enfant_id': enfantId,
    'date_jour': dateJour,
    'type_allaitement': typeAllaitement,
    'g1_to_g8': g1ToG8,
    'score_diversite': scoreDiversite,
    'notes': notes,
    ...syncColumns,
  };
}
