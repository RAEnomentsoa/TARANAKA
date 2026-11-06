import 'model.dart';

class Profile extends Model {
  const Profile({super.id, required this.type, this.consentement});

  factory Profile.fromMap(Map<String, Object?> map) => Profile(
    id: map['id'] as int?,
    type: map['type'] as String,
    consentement: switch (map['consentement'] as int?) {
      null => null,
      final v => v != 0,
    },
  );

  static const String table = 'profile';

  final String type;
  final bool? consentement;

  @override
  Map<String, Object?> toMap() => {
    'id': ?id,
    'type': type,
    'consentement': switch (consentement) {
      null => null,
      true => 1,
      false => 0,
    },
  };
}
