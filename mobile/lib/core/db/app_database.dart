import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import 'db_opener.dart';
import 'schema.dart';

/// One encrypted database per profile.
class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Database db;
  final String path;

  static Future<AppDatabase> open(
    DbOpener opener,
    String path,
    String passphrase, {
    List<List<String>>? steps,
  }) async {
    final all = steps ?? migrations;
    Future<void> run(DatabaseExecutor db, int from, int to) async {
      for (var v = from; v < to; v++) {
        for (final sql in all[v]) {
          await db.execute(sql);
        }
      }
    }

    final db = await opener.open(
      path,
      passphrase: passphrase,
      version: all.length,
      onCreate: (db, version) => run(db, 0, version),
      onUpgrade: (db, from, to) => run(db, from, to),
    );
    // Proves the key is right (SQLCipher only fails on first read).
    await db.rawQuery('SELECT count(*) FROM sqlite_master');
    return AppDatabase._(db, path);
  }

  Future<void> close() => db.close();

  // ---- meta key/value

  Future<String?> getMeta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await db.delete('meta', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('meta', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, Object?>?> getMetaJson(String key) async {
    final raw = await getMeta(key);
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  Future<void> setMetaJson(String key, Map<String, Object?>? value) =>
      setMeta(key, value == null ? null : jsonEncode(value));

  Future<bool> getFlag(String key, {bool fallback = false}) async {
    final raw = await getMeta(key);
    return raw == null ? fallback : raw == '1';
  }

  Future<void> setFlag(String key, bool value) => setMeta(key, value ? '1' : '0');
}
