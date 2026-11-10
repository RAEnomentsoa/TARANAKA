import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/db/app_database.dart';
import 'package:taranaka/core/growth/who_lms.dart';
import 'package:taranaka/core/security/pin_crypto.dart';
import 'package:taranaka/core/sync/outbox.dart';
import 'package:taranaka/core/sync/sync_status.dart';
import 'package:taranaka/features/child/data/child_repository.dart';

import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;
  late AppDatabase db;
  late ChildRepository repo;
  final key = PinCrypto.passphrase(PinCrypto().randomBytes());

  setUp(() async {
    env = await TestEnv.create();
    db = await AppDatabase.open(env.services.dbOpener, '${env.dir.path}/p.db', key);
    repo = ChildRepository(db, clock: env.clock);
  });

  tearDown(() async {
    await db.close();
    env.dir.deleteSync(recursive: true);
  });

  test('children stay on the phone ("Enregistré"), nothing is queued for sync', () async {
    final c = await repo.addChild(
      name: 'Kanto',
      sex: 'M',
      birthDate: DateTime(2026, 2, 1),
      birthWeightKg: 3.1,
    );
    expect(c.birthWeightKg, 3.1);
    expect(c.child.syncStatus, SyncStatus.saved);
    await repo.addGrowth(
      child: c,
      date: DateTime(2026, 11, 4),
      weightKg: 8.2,
      lengthCm: 70,
      position: 'couche',
      tables: WhoTables.empty,
      alerte: 'vert',
    );
    expect(await Outbox.count(db.db), 0);
  });

  test('growth: age and length correction computed, no z-score without WHO tables', () async {
    final c = await repo.addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1));
    final g = await repo.addGrowth(
      child: c,
      date: DateTime(2026, 11, 4),
      weightKg: 8.2,
      lengthCm: 70,
      position: 'debout',
      tables: WhoTables.empty,
      alerte: 'vert',
    );
    expect(g.ageDays, 276);
    expect(g.correctedLengthCm, 70.7);
    expect(g.z.any, isFalse);
  });

  test('feeding: one row per day, saved again replaces it, survives reopening', () async {
    final c = await repo.addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1));
    final day = DateTime(2026, 11, 4);
    await repo.saveFeeding(
      c.id,
      FeedingLog(date: day, breastfeeding: 'mixte', foods: {'vary'}, meals: 1, milkFeeds: 0),
    );
    await repo.saveFeeding(
      c.id,
      FeedingLog(
        date: day,
        breastfeeding: 'mixte',
        foods: {'vary', 'anana', 'lait_maternel'},
        meals: 3,
        milkFeeds: 0,
      ),
    );
    await db.close();
    db = await AppDatabase.open(env.services.dbOpener, '${env.dir.path}/p.db', key);
    repo = ChildRepository(db, clock: env.clock);
    final log = (await repo.feeding(c.id, day))!;
    expect(log.foods, {'vary', 'anana', 'lait_maternel'});
    expect(log.meals, 3);
    expect((await repo.feedingSince(c.id, DateTime(2026, 11, 1))).length, 1);
  });

  test('vaccines: mark done, undo', () async {
    final c = await repo.addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1));
    await repo.markVaccine(c.id, 'bcg', DateTime(2026, 2, 2));
    expect((await repo.vaccinesDone(c.id))['bcg'], DateTime(2026, 2, 2));
    await repo.unmarkVaccine(c.id, 'bcg');
    expect(await repo.vaccinesDone(c.id), isEmpty);
  });

  test('deleting a child deletes its measurements, meals and vaccines', () async {
    final c = await repo.addChild(name: 'Kanto', sex: 'M', birthDate: DateTime(2026, 2, 1));
    await repo.markVaccine(c.id, 'bcg', DateTime(2026, 2, 2));
    await repo.saveFeeding(
      c.id,
      FeedingLog(date: DateTime(2026, 11, 4), breastfeeding: 'aucun', foods: {}, meals: 0, milkFeeds: 0),
    );
    await repo.deleteChild(c.id);
    expect(await db.db.query('vaccin_fait'), isEmpty);
    expect(await db.db.query('journal_alimentaire'), isEmpty);
  });
}
