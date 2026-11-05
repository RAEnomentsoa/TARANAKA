import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

/// Opens a profile database. On the phone it is SQLCipher (AES-256, key from
/// the profile's master key). Tests use an FFI opener on the host.
abstract interface class DbOpener {
  Future<Database> open(
    String path, {
    required String passphrase,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  });

  Future<void> delete(String path);
}

class SqlCipherOpener implements DbOpener {
  const SqlCipherOpener();

  @override
  Future<Database> open(
    String path, {
    required String passphrase,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  }) => cipher.openDatabase(
    path,
    password: passphrase,
    version: version,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: onCreate,
    onUpgrade: onUpgrade,
  );

  @override
  Future<void> delete(String path) => cipher.deleteDatabase(path);
}
