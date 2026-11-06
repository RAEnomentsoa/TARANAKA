import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'database_schema.dart';

/// Ouvre la base SQLite locale et en partage l'unique connexion.
class DatabaseHelper {
  DatabaseHelper({this._path});

  static const String _fileName = 'taranaka.db';
  static const int _version = 1;

  final String? _path;
  Future<Database>? _database;

  /// Mémorise le `Future` pour que des appels simultanés partagent une seule
  /// ouverture.
  Future<Database> get database => _database ??= _open();

  Future<Database> _open() async {
    final path = _path ?? join(await getDatabasesPath(), _fileName);
    return openDatabase(
      path,
      version: _version,
      // Les clés étrangères sont désactivées par défaut dans SQLite et le
      // réglage ne vaut que pour la connexion en cours : il doit être appliqué
      // à chaque ouverture, avant toute transaction.
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        final batch = db.batch();
        createTableStatements.forEach(batch.execute);
        await batch.commit(noResult: true);
      },
    );
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await (await database)?.close();
  }
}
