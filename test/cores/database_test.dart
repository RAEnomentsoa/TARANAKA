import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taranaka/cores/data/database_helper.dart';
import 'package:taranaka/cores/models/models.dart';
import 'package:taranaka/cores/providers/cycle_providers.dart';
import 'package:taranaka/cores/providers/table_providers.dart';

void main() {
  late DatabaseHelper helper;
  late ProviderContainer container;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    helper = DatabaseHelper(path: inMemoryDatabasePath);
    container = ProviderContainer.test(
      overrides: [
        databaseHelperProvider.overrideWithValue(helper),
        deviceIdProvider.overrideWith((ref) async => 'test-device'),
      ],
    );
  });

  tearDown(() => helper.close());

  /// Un modèle entièrement renseigné pour chaque table : chaque `toMap` doit
  /// couvrir exactement les colonnes du schéma.
  final samples = <Model>[
    const Province(nom: 'Antananarivo'),
    const Profile(type: 'mere', consentement: true),
    const Region(nom: 'Analamanga'),
    const Csb(name: 'CSB II'),
    const User(nom: 'Rabe', pinHash: 'hash'),
    const Grossesse(ddr: '2026-01-01', dpa: '2026-10-08'),
    const TypeDangerGrossesse(description: 'Hémorragie'),
    const DangerGrossesse(),
    const Cycle(dureCycle: 28),
    const Enfant(nom: 'Soa'),
    const ReferenceOms(indicateur: 'WHZ', m: 1.5, l: 0.5, s: 0.1),
    const Mesure(poidsKg: 8.5, whz: -2.1),
    const JournalAlimentaire(g1ToG8: '10101010', scoreDiversite: 4),
    const Referencement(codeUnique: 'R-1'),
    const ConsultationNutritionnelle(decision: 'suivi'),
  ];

  test('les clés étrangères sont actives à chaque ouverture', () async {
    for (var i = 0; i < 2; i++) {
      final db = await helper.database;
      final rows = await db.rawQuery('PRAGMA foreign_keys');
      expect(rows.single['foreign_keys'], 1);
      await helper.close();
    }
  });

  test(
    'chaque modèle correspond exactement aux colonnes de sa table',
    () async {
      final db = await helper.database;
      final tables = <Model, String>{
        for (final (i, name) in const [
          Province.table,
          Profile.table,
          Region.table,
          Csb.table,
          User.table,
          Grossesse.table,
          TypeDangerGrossesse.table,
          DangerGrossesse.table,
          Cycle.table,
          Enfant.table,
          ReferenceOms.table,
          Mesure.table,
          JournalAlimentaire.table,
          Referencement.table,
          ConsultationNutritionnelle.table,
        ].indexed)
          samples[i]: name,
      };
      for (final MapEntry(key: model, value: table) in tables.entries) {
        final info = await db.rawQuery('PRAGMA table_info("$table")');
        final columns = info.map((c) => c['name']).toSet();
        expect({...model.toMap().keys, 'id'}, columns, reason: table);
      }
    },
  );

  group('CRUD via les providers', () {
    test(
      'tous les providers insèrent, lisent, modifient et suppriment',
      () async {
        Future<void> check<T extends Model>(
          AsyncNotifierProvider<dynamic, List<T>> provider,
          T sample,
        ) async {
          await container.read(provider.future);
          final notifier = container.read(provider.notifier);
          final T created = await notifier.add(sample);
          expect(created.id, isNotNull, reason: '$T');
          expect(await container.read(provider.future), hasLength(1));
          expect(await notifier.edit(created), isTrue, reason: '$T');
          expect(await notifier.remove(created.id!), isTrue, reason: '$T');
          expect(await container.read(provider.future), isEmpty, reason: '$T');
        }

        await check(provincesProvider, samples[0] as Province);
        await check(profilesProvider, samples[1] as Profile);
        await check(regionsProvider, samples[2] as Region);
        await check(csbsProvider, samples[3] as Csb);
        await check(usersProvider, samples[4] as User);
        await check(grossessesProvider, samples[5] as Grossesse);
        await check(
          typesDangerGrossesseProvider,
          samples[6] as TypeDangerGrossesse,
        );
        await check(dangersGrossesseProvider, samples[7] as DangerGrossesse);
        await check(cyclesProvider, samples[8] as Cycle);
        await check(enfantsProvider, samples[9] as Enfant);
        await check(referencesOmsProvider, samples[10] as ReferenceOms);
        await check(mesuresProvider, samples[11] as Mesure);
        await check(
          journauxAlimentairesProvider,
          samples[12] as JournalAlimentaire,
        );
        await check(referencementsProvider, samples[13] as Referencement);
        await check(
          consultationsNutritionnellesProvider,
          samples[14] as ConsultationNutritionnelle,
        );
      },
    );

    test('les valeurs relues sont celles écrites', () async {
      final repository = container.read(referenceOmsRepositoryProvider);
      final created = await repository.insert(samples[10] as ReferenceOms);
      final read = await repository.getById(created.id!);
      expect(read!.toMap(), created.toMap());

      final profiles = container.read(profileRepositoryProvider);
      final profile = await profiles.insert(samples[1] as Profile);
      expect((await profiles.getById(profile.id!))!.consentement, isTrue);

      final types = container.read(typeDangerGrossesseRepositoryProvider);
      final type = await types.insert(samples[6] as TypeDangerGrossesse);
      expect((await types.getById(type.id!))!.description, 'Hémorragie');
    });
  });

  group('colonnes de synchronisation', () {
    test('sont renseignées à la création', () async {
      final created = await container
          .read(userRepositoryProvider)
          .insert(const User(nom: 'Rabe', version: 9, syncStatus: 'synced'));
      expect(created.version, 1);
      expect(created.syncStatus, SyncStatus.pending);
      expect(created.deviceId, 'test-device');
      expect(created.updatedAt, isNotNull);
    });

    test('la mise à jour incrémente la version enregistrée', () async {
      final repository = container.read(userRepositoryProvider);
      final created = await repository.insert(const User(nom: 'Rabe'));
      // Objet reconstruit sans version : la base fait référence.
      await repository.update(User(id: created.id, nom: 'Rakoto'));
      await repository.update(User(id: created.id, nom: 'Rasoa'));
      final read = await repository.getById(created.id!);
      expect(read!.nom, 'Rasoa');
      expect(read.version, 3);
    });

    test('la suppression est logique et bloque les écritures', () async {
      final repository = container.read(userRepositoryProvider);
      final created = await repository.insert(const User(nom: 'Rabe'));
      expect(await repository.delete(created.id!), isTrue);
      expect(await repository.getById(created.id!), isNull);
      expect(await repository.getAll(), isEmpty);
      expect(await repository.delete(created.id!), isFalse);
      expect(await repository.update(User(id: created.id, nom: 'X')), isFalse);

      final db = await helper.database;
      final row = (await db.query(User.table)).single;
      expect(row['deleted_at'], isNotNull);
      expect(row['version'], 2);
      expect(row['sync_status'], SyncStatus.pending);
    });
  });

  group('clés étrangères', () {
    test('une référence inexistante est refusée', () async {
      await expectLater(
        container
            .read(regionRepositoryProvider)
            .insert(const Region(nom: 'Orpheline', idProvince: 999)),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('ON DELETE SET NULL met aussi à jour la liste dépendante', () async {
      final province = await container
          .read(provincesProvider.notifier)
          .add(const Province(nom: 'P'));
      await container
          .read(regionsProvider.notifier)
          .add(Region(nom: 'R', idProvince: province.id));
      expect(
        (await container.read(regionsProvider.future)).single.idProvince,
        province.id,
      );

      await container.read(provincesProvider.notifier).remove(province.id!);

      expect(await container.read(provincesProvider.future), isEmpty);
      expect(
        (await container.read(regionsProvider.future)).single.idProvince,
        isNull,
      );
    });

    test('ON DELETE CASCADE supprime les lignes enfants', () async {
      final db = await helper.database;
      final userId = await db.insert(User.table, {'nom': 'Rabe'});
      await db.insert(Cycle.table, {'User_id': userId});
      await db.delete(User.table, where: 'id = ?', whereArgs: [userId]);
      expect(await db.query(Cycle.table), isEmpty);
    });
  });

  group('journal des cycles', () {
    Future<List<Map<String, Object?>>> cycleRows() async =>
        (await helper.database).query(Cycle.table, orderBy: 'date_debut');

    test(
      'une création renseigne toutes les colonnes en une écriture',
      () async {
        final userId =
            (await container
                    .read(usersProvider.notifier)
                    .add(const User(nom: 'Soa')))
                .id;

        await container
            .read(cycleJournalProvider)
            .save(const Cycle(dateDebut: '2026-01-01'));

        final row = (await cycleRows()).single;
        expect(row['date_fin'], isNull);
        expect(row['intensite'], isNull);
        expect(row['symptome'], isNull);
        expect(row['dure_cycle'], isNull);
        expect(row['dure_regle'], 5);
        expect(row['estimationProchain'], '2026-01-29');
        expect(row['User_id'], userId);
        expect(row['version'], 1);
        expect(row['sync_status'], 'pending');
        expect(row['device_id'], 'test-device');
        expect(DateTime.parse(row['updated_at']! as String).isUtc, isTrue);
      },
    );

    test('sans compte local, User_id reste NULL', () async {
      await container
          .read(cycleJournalProvider)
          .save(const Cycle(dateDebut: '2026-01-01'));
      expect((await cycleRows()).single['User_id'], isNull);
    });

    test('un nouveau cycle mesure le précédent et réajuste la suite', () async {
      final journal = container.read(cycleJournalProvider);
      await journal.save(const Cycle(dateDebut: '2026-01-01'));
      await journal.save(const Cycle(dateDebut: '2026-01-31'));

      final rows = await cycleRows();
      expect(rows.map((r) => r['dure_cycle']), [30, null]);
      expect(rows.map((r) => r['version']), [2, 1]);
      expect(rows[0]['estimationProchain'], '2026-01-29');
      expect(rows[1]['estimationProchain'], '2026-03-02');
    });

    test('supprimer le dernier cycle rouvre le précédent', () async {
      final journal = container.read(cycleJournalProvider);
      await journal.save(const Cycle(dateDebut: '2026-01-01'));
      await journal.save(const Cycle(dateDebut: '2026-01-31'));

      await journal.remove((await cycleRows())[1]['id']! as int);

      final remaining = await container.read(cyclesProvider.future);
      expect(remaining.single.dureCycle, isNull);
      expect(remaining.single.estimationProchain, '2026-01-29');
    });
  });
}
