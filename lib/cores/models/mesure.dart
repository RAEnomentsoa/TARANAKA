import 'model.dart';

class Mesure extends SyncableModel {
  const Mesure({
    super.id,
    this.enfantId,
    this.dateMesure,
    this.poidsKg,
    this.tailleCm,
    this.position,
    this.pbMm,
    this.oedemesBilateraux,
    this.whz,
    this.alerte,
    this.ageJour,
    this.ageMois,
    this.tailleCorrigeeEnCm,
    this.waz,
    this.haz,
    this.flagAberrant,
    this.motifAlerte,
    this.refOms,
    this.aiscId,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory Mesure.fromMap(Map<String, Object?> map) => Mesure(
    id: map['id'] as int?,
    enfantId: map['enfant_id'] as int?,
    dateMesure: map['date_mesure'] as String?,
    poidsKg: (map['poids_kg'] as num?)?.toDouble(),
    tailleCm: (map['taille_cm'] as num?)?.toDouble(),
    position: map['position'] as String?,
    pbMm: (map['pb_mm'] as num?)?.toDouble(),
    oedemesBilateraux: map['oedemes_bilateraux'] as String?,
    whz: (map['whz'] as num?)?.toDouble(),
    alerte: map['alerte'] as String?,
    ageJour: map['age_jour'] as int?,
    ageMois: map['age_mois'] as int?,
    tailleCorrigeeEnCm: (map['taille_corrigee_en_cm'] as num?)?.toDouble(),
    waz: (map['waz'] as num?)?.toDouble(),
    haz: (map['haz'] as num?)?.toDouble(),
    flagAberrant: map['flag_aberrant'] as String?,
    motifAlerte: map['motif_alerte'] as String?,
    refOms: map['ref_oms'] as String?,
    aiscId: map['aisc_id'] as String?,
    version: map['version'] as int? ?? 1,
    updatedAt: map['updated_at'] as String?,
    deviceId: map['device_id'] as String?,
    deletedAt: map['deleted_at'] as String?,
    syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
  );

  static const String table = 'Mesure';

  final int? enfantId;
  final String? dateMesure;
  final double? poidsKg;
  final double? tailleCm;
  final String? position;
  final double? pbMm;
  final String? oedemesBilateraux;
  final double? whz;
  final String? alerte;
  final int? ageJour;
  final int? ageMois;
  final double? tailleCorrigeeEnCm;
  final double? waz;
  final double? haz;
  final String? flagAberrant;
  final String? motifAlerte;
  final String? refOms;
  final String? aiscId;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'enfant_id': enfantId,
    'date_mesure': dateMesure,
    'poids_kg': poidsKg,
    'taille_cm': tailleCm,
    'position': position,
    'pb_mm': pbMm,
    'oedemes_bilateraux': oedemesBilateraux,
    'whz': whz,
    'alerte': alerte,
    'age_jour': ageJour,
    'age_mois': ageMois,
    'taille_corrigee_en_cm': tailleCorrigeeEnCm,
    'waz': waz,
    'haz': haz,
    'flag_aberrant': flagAberrant,
    'motif_alerte': motifAlerte,
    'ref_oms': refOms,
    'aisc_id': aiscId,
    ...syncColumns,
  };
}
