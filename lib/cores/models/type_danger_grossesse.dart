import 'model.dart';

class TypeDangerGrossesse extends Model {
  const TypeDangerGrossesse({super.id, this.description});

  factory TypeDangerGrossesse.fromMap(Map<String, Object?> map) =>
      TypeDangerGrossesse(
        id: map['id'] as int?,
        description: map['Desc'] as String?,
      );

  static const String table = 'Type_Danger_Grossesse';

  final String? description;

  @override
  Map<String, Object?> toMap() => {'id': ?id, 'Desc': description};
}
