import 'model.dart';

class Enfant extends SyncableModel {
  const Enfant({
    super.id,
    this.idUser,
    this.idGrossesse,
    this.dateDeNaissance,
    this.sexe,
    this.statutPriseEnCharge,
    this.nom,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory Enfant.fromMap(Map<String, Object?> map) => Enfant(
    id: map['id'] as int?,
    idUser: map['id_User'] as int?,
    idGrossesse: map['id_Grossesse'] as int?,
    dateDeNaissance: map['date_de_naissance'] as String?,
    sexe: map['sexe'] as String?,
    statutPriseEnCharge: map['statut_prise_en_charge'] as String?,
    nom: map['nom'] as String?,
    version: map['version'] as int? ?? 1,
    updatedAt: map['updated_at'] as String?,
    deviceId: map['device_id'] as String?,
    deletedAt: map['deleted_at'] as String?,
    syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
  );

  static const String table = 'Enfant';

  final int? idUser;
  final int? idGrossesse;
  final String? dateDeNaissance;
  final String? sexe;
  final String? statutPriseEnCharge;
  final String? nom;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'id_User': idUser,
    'id_Grossesse': idGrossesse,
    'date_de_naissance': dateDeNaissance,
    'sexe': sexe,
    'statut_prise_en_charge': statutPriseEnCharge,
    'nom': nom,
    ...syncColumns,
  };
}
