import 'model.dart';

class Province extends Model {
  const Province({super.id, required this.nom});

  factory Province.fromMap(Map<String, Object?> map) =>
      Province(id: map['id'] as int?, nom: map['nom'] as String);

  static const String table = 'Province';

  final String nom;

  @override
  Map<String, Object?> toMap() => {'id': ?id, 'nom': nom};
}
