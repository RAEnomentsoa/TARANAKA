import 'model.dart';

class User extends SyncableModel {
  const User({
    super.id,
    this.nom,
    this.prenom,
    this.email,
    this.phone,
    this.role,
    this.pinHash,
    this.dateCreation,
    this.idProfile,
    this.idRegion,
    super.version,
    super.updatedAt,
    super.deviceId,
    super.deletedAt,
    super.syncStatus,
  });

  factory User.fromMap(Map<String, Object?> map) => User(
    id: map['id'] as int?,
    nom: map['nom'] as String?,
    prenom: map['prenom'] as String?,
    email: map['email'] as String?,
    phone: map['phone'] as String?,
    role: map['role'] as String?,
    pinHash: map['pin_hash'] as String?,
    dateCreation: map['dateCreation'] as String?,
    idProfile: map['id_profile'] as int?,
    idRegion: map['id_region'] as int?,
    version: map['version'] as int? ?? 1,
    updatedAt: map['updated_at'] as String?,
    deviceId: map['device_id'] as String?,
    deletedAt: map['deleted_at'] as String?,
    syncStatus: map['sync_status'] as String? ?? SyncStatus.pending,
  );

  static const String table = 'User';

  final String? nom;
  final String? prenom;
  final String? email;
  final String? phone;
  final String? role;
  final String? pinHash;
  final String? dateCreation;
  final int? idProfile;
  final int? idRegion;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'nom': nom,
    'prenom': prenom,
    'email': email,
    'phone': phone,
    'role': role,
    'pin_hash': pinHash,
    'dateCreation': dateCreation,
    'id_profile': idProfile,
    'id_region': idRegion,
    ...syncColumns,
  };
}
