import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/db/app_database.dart';
import 'package:taranaka/core/db/schema.dart';
import 'package:taranaka/core/security/pin_crypto.dart';

import '../../helpers/test_env.dart';

void main() {
  late Directory dir;
  final opener = FfiCipherOpener();
  final key = PinCrypto.passphrase(PinCrypto().randomBytes());

  setUp(() => dir = Directory.systemTemp.createTempSync('taranaka_db'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the database file is encrypted (SQLCipher) and survives a reopen', () async {
    final path = '${dir.path}/p.db';
    final db = await AppDatabase.open(opener, path, key);
    await db.setMeta('note', 'Saignement vaginal – secret');
    await db.close();

    final bytes = await File(path).readAsBytes();
    // A plain SQLite file starts with "SQLite format 3".
    expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
    expect(String.fromCharCodes(bytes).contains('Saignement'), isFalse);

    final again = await AppDatabase.open(opener, path, key);
    expect(await again.getMeta('note'), 'Saignement vaginal – secret');
    await again.close();
  });

  test('a wrong key cannot open the database', () async {
    final path = '${dir.path}/p.db';
    await (await AppDatabase.open(opener, path, key)).close();
    final wrong = PinCrypto.passphrase(PinCrypto().randomBytes());
    expect(() => AppDatabase.open(opener, path, wrong), throwsA(anything));
  });

  test('migrations run in order on create and on upgrade', () async {
    final path = '${dir.path}/m.db';
    final v1 = [
      ['CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)'],
    ];
    final db1 = await AppDatabase.open(opener, path, key, steps: v1);
    await db1.setMeta('a', '1');
    await db1.close();

    final v2 = [
      ...v1,
      ['CREATE TABLE extra (id TEXT PRIMARY KEY)'],
    ];
    final db2 = await AppDatabase.open(opener, path, key, steps: v2);
    expect(await db2.getMeta('a'), '1');
    await db2.db.insert('extra', {'id': 'x'});
    expect((await db2.db.rawQuery('PRAGMA user_version')).first.values.first, 2);
    await db2.close();
  });

  test('v12 (D16): rows of an older version get a sync id and are kept', () async {
    final path = '${dir.path}/v11.db';
    final old = await AppDatabase.open(opener, path, key, steps: migrations.sublist(0, 11));
    const at = '2026-10-01T08:00:00Z';
    await old.db.insert('enfant', {
      'id': 'enf-1',
      'nom': 'Kanto',
      'sexe': 'M',
      'date_naissance': '2026-02-01',
      'created_at': at,
      'updated_at': at,
    });
    for (final code in ['bcg', 'polio_0']) {
      await old.db.insert('vaccin_fait', {
        'enfant_id': 'enf-1',
        'code': code,
        'date_faite': '2026-02-02',
        'created_at': at,
      });
    }
    await old.db.insert('cycle_jour', {'date_jour': '2026-10-02', 'created_at': at, 'updated_at': at});
    await old.close();

    final db = await AppDatabase.open(opener, path, key);
    expect((await db.db.rawQuery('PRAGMA user_version')).first.values.first, migrations.length);
    final vaccines = await db.db.query('vaccin_fait', orderBy: 'code');
    expect(vaccines.map((v) => v['code']), ['bcg', 'polio_0']);
    final ids = {for (final v in vaccines) v['id']};
    expect(ids, hasLength(2), reason: 'one distinct id per row');
    expect(ids.every((id) => id is String && id.length == 36), isTrue);
    expect(vaccines.first['version'], 1);
    final day = (await db.db.query('cycle_jour')).single;
    expect(day['id'], isA<String>());
    // The agent's view of the beneficiaries exists.
    await db.db.insert('beneficiaire', {'id': 'mere-1', 'prenom': 'Voahangy', 'nom': '', 'updated_at': at});
    await db.close();
  });

  test('flags and JSON values', () async {
    final db = await AppDatabase.open(opener, '${dir.path}/f.db', key);
    expect(await db.getFlag('sync'), isFalse);
    await db.setFlag('sync', true);
    expect(await db.getFlag('sync'), isTrue);
    await db.setMetaJson('obj', {'a': 1});
    expect(await db.getMetaJson('obj'), {'a': 1});
    await db.setMeta('obj', null);
    expect(await db.getMeta('obj'), isNull);
    await db.close();
  });
}
