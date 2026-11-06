import 'model.dart';

class ConsultationNutritionnelle extends SyncableModel {
  const ConsultationNutritionnelle({
    super.id,
    this.idMesure,
    this.enfantId,
    this.date,
    this.decision,
    this.csbId,
    this.diagnostic,
    this.referencementId,
    this.agentMedicalId,
    this.observations,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory ConsultationNutritionnelle.fromMap(Map<String, Object?> map) =>
      ConsultationNutritionnelle(
        id: map['id'] as int?,
        idMesure: map['id_mesure'] as int?,
        enfantId: map['enfant_id'] as int?,
        date: map['date'] as String?,
        decision: map['decision'] as String?,
        csbId: map['csb_id'] as int?,
        diagnostic: map['diagnostic'] as String?,
        referencementId: map['referencement_id'] as int?,
        agentMedicalId: map['Agent_medical_id'] as int?,
        observations: map['observations'] as String?,
        version: map['version'] as int? ?? 1,
        updatedAt: map['updated_at'] as String?,
        deviceId: map['device_id'] as String?,
        deletedAt: map['deleted_at'] as String?,
        syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
      );

  static const String table = 'consultation_nutritionnelle';

  final int? idMesure;
  final int? enfantId;
  final String? date;
  final String? decision;
  final int? csbId;
  final String? diagnostic;
  final int? referencementId;
  final int? agentMedicalId;
  final String? observations;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'id_mesure': idMesure,
    'enfant_id': enfantId,
    'date': date,
    'decision': decision,
    'csb_id': csbId,
    'diagnostic': diagnostic,
    'referencement_id': referencementId,
    'Agent_medical_id': agentMedicalId,
    'observations': observations,
    ...syncColumns,
  };
}
