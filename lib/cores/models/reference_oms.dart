import 'model.dart';

class ReferenceOms extends Model {
  const ReferenceOms({
    super.id,
    this.indicateur,
    this.sexe,
    this.cle,
    this.m,
    this.l,
    this.s,
    this.measureType,
  });

  factory ReferenceOms.fromMap(Map<String, Object?> map) => ReferenceOms(
    id: map['id'] as int?,
    indicateur: map['Indicateur'] as String?,
    sexe: map['sexe'] as String?,
    cle: map['cLe'] as String?,
    m: (map['M'] as num?)?.toDouble(),
    l: (map['L'] as num?)?.toDouble(),
    s: (map['S'] as num?)?.toDouble(),
    measureType: map['Measure_Type'] as String?,
  );

  static const String table = 'reference_oms';

  final String? indicateur;
  final String? sexe;
  final String? cle;
  final double? m;
  final double? l;
  final double? s;
  final String? measureType;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'Indicateur': indicateur,
    'sexe': sexe,
    'cLe': cle,
    'M': m,
    'L': l,
    'S': s,
    'Measure_Type': measureType,
  };
}
