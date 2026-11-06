import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database_helper.dart';
import '../data/device_id.dart';
import '../data/table_repository.dart';
import '../models/models.dart';
import 'crud_notifier.dart';

final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  final helper = DatabaseHelper();
  ref.onDispose(helper.close);
  return helper;
});

final deviceIdProvider = FutureProvider<String>(
  (ref) => loadOrCreateDeviceId(),
);

typedef _FromMap<T> = T Function(Map<String, Object?> map);
typedef _TableProvider<T extends Model> =
    AsyncNotifierProvider<CrudNotifier<T>, List<T>>;

Provider<TableRepository<T>> _repository<T extends Model>(
  String table,
  _FromMap<T> fromMap,
) => Provider<TableRepository<T>>(
  (ref) =>
      TableRepository<T>(ref.watch(databaseHelperProvider), table, fromMap),
);

Provider<TableRepository<T>> _syncableRepository<T extends SyncableModel>(
  String table,
  _FromMap<T> fromMap,
) => Provider<TableRepository<T>>(
  (ref) => SyncableRepository<T>(
    ref.watch(databaseHelperProvider),
    table,
    fromMap,
    () => ref.read(deviceIdProvider.future),
  ),
);

_TableProvider<T> _table<T extends Model>(
  Provider<TableRepository<T>> repository,
) => AsyncNotifierProvider(() => CrudNotifier<T>(repository));

// Tables de référence : suppression physique.

final provinceRepositoryProvider = _repository<Province>(
  Province.table,
  Province.fromMap,
);
final provincesProvider = _table(provinceRepositoryProvider);

final profileRepositoryProvider = _repository<Profile>(
  Profile.table,
  Profile.fromMap,
);
final profilesProvider = _table(profileRepositoryProvider);

final regionRepositoryProvider = _repository<Region>(
  Region.table,
  Region.fromMap,
);
final regionsProvider = _table(regionRepositoryProvider);

final csbRepositoryProvider = _repository<Csb>(Csb.table, Csb.fromMap);
final csbsProvider = _table(csbRepositoryProvider);

final typeDangerGrossesseRepositoryProvider = _repository<TypeDangerGrossesse>(
  TypeDangerGrossesse.table,
  TypeDangerGrossesse.fromMap,
);
final typesDangerGrossesseProvider = _table(
  typeDangerGrossesseRepositoryProvider,
);

final referenceOmsRepositoryProvider = _repository<ReferenceOms>(
  ReferenceOms.table,
  ReferenceOms.fromMap,
);
final referencesOmsProvider = _table(referenceOmsRepositoryProvider);

// Tables synchronisées : suppression logique via `deleted_at`.

final userRepositoryProvider = _syncableRepository<User>(
  User.table,
  User.fromMap,
);
final usersProvider = _table(userRepositoryProvider);

final grossesseRepositoryProvider = _syncableRepository<Grossesse>(
  Grossesse.table,
  Grossesse.fromMap,
);
final grossessesProvider = _table(grossesseRepositoryProvider);

final dangerGrossesseRepositoryProvider = _syncableRepository<DangerGrossesse>(
  DangerGrossesse.table,
  DangerGrossesse.fromMap,
);
final dangersGrossesseProvider = _table(dangerGrossesseRepositoryProvider);

final cycleRepositoryProvider = _syncableRepository<Cycle>(
  Cycle.table,
  Cycle.fromMap,
);
final cyclesProvider = _table(cycleRepositoryProvider);

final enfantRepositoryProvider = _syncableRepository<Enfant>(
  Enfant.table,
  Enfant.fromMap,
);
final enfantsProvider = _table(enfantRepositoryProvider);

final mesureRepositoryProvider = _syncableRepository<Mesure>(
  Mesure.table,
  Mesure.fromMap,
);
final mesuresProvider = _table(mesureRepositoryProvider);

final journalAlimentaireRepositoryProvider =
    _syncableRepository<JournalAlimentaire>(
      JournalAlimentaire.table,
      JournalAlimentaire.fromMap,
    );
final journauxAlimentairesProvider = _table(
  journalAlimentaireRepositoryProvider,
);

final referencementRepositoryProvider = _syncableRepository<Referencement>(
  Referencement.table,
  Referencement.fromMap,
);
final referencementsProvider = _table(referencementRepositoryProvider);

final consultationNutritionnelleRepositoryProvider =
    _syncableRepository<ConsultationNutritionnelle>(
      ConsultationNutritionnelle.table,
      ConsultationNutritionnelle.fromMap,
    );
final consultationsNutritionnellesProvider = _table(
  consultationNutritionnelleRepositoryProvider,
);
