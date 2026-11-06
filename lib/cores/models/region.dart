import 'model.dart';

class Region extends Model {
  const Region({super.id, required this.nom, this.idProvince});

  factory Region.fromMap(Map<String, Object?> map) => Region(
    id: map['id'] as int?,
    nom: map['nom'] as String,
    idProvince: map['id_province'] as int?,
  );

  static const String table = 'Region';

  final String nom;
  final int? idProvince;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'nom': nom,
    'id_province': idProvince,
  };
}
