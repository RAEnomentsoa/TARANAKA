import 'model.dart';

class Csb extends Model {
  const Csb({super.id, required this.name, this.idRegion});

  factory Csb.fromMap(Map<String, Object?> map) => Csb(
    id: map['id'] as int?,
    name: map['name'] as String,
    idRegion: map['id_region'] as int?,
  );

  static const String table = 'CSB';

  final String name;
  final int? idRegion;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'name': name,
    'id_region': idRegion,
  };
}
