import 'package:sqflite/sqflite.dart';

import '../models/model.dart';
import 'database_helper.dart';

/// CRUD d'une table, avec suppression physique.
class TableRepository<T extends Model> {
  TableRepository(this._helper, this.table, this.fromMap);

  final DatabaseHelper _helper;
  final String table;
  final T Function(Map<String, Object?> map) fromMap;

  Future<Database> get _db => _helper.database;

  /// Condition appliquée à toutes les lectures.
  String? get _baseWhere => null;

  Future<List<T>> getAll({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final conditions = [_baseWhere, where].nonNulls.map((c) => '($c)');
    final rows = await (await _db).query(
      table,
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
    return rows.map(fromMap).toList();
  }

  Future<T?> getById(int id) async {
    final items = await getAll(where: 'id = ?', whereArgs: [id]);
    return items.isEmpty ? null : items.first;
  }

  /// Insère [item] et le renvoie tel qu'enregistré, avec son `id`.
  Future<T> insert(T item) async {
    final map = await _valuesForInsert(item);
    final id = await (await _db).insert(table, map);
    return fromMap({...map, 'id': id});
  }

  Future<Map<String, Object?>> _valuesForInsert(T item) async => item.toMap();

  /// Renvoie `false` si la ligne n'existe pas.
  Future<bool> update(T item) async {
    final count = await (await _db).update(
      table,
      item.toMap(),
      where: 'id = ?',
      whereArgs: [_requireId(item)],
    );
    return count > 0;
  }

  /// Renvoie `false` si la ligne n'existe pas.
  Future<bool> delete(int id) async {
    final count = await (await _db).delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  int _requireId(T item) =>
      item.id ??
      (throw ArgumentError('$table : id requis pour la mise à jour'));
}

/// CRUD d'une table synchronisée : tient à jour les colonnes de synchronisation
/// et remplace la suppression physique par `deleted_at`, pour que la suppression
/// puisse être transmise au serveur.
class SyncableRepository<T extends SyncableModel> extends TableRepository<T> {
  SyncableRepository(super.helper, super.table, super.fromMap, this._deviceId);

  final Future<String> Function() _deviceId;

  @override
  String get _baseWhere => 'deleted_at IS NULL';

  String get _now => DateTime.now().toUtc().toIso8601String();

  @override
  Future<Map<String, Object?>> _valuesForInsert(T item) async => {
    ...item.toMap(),
    'version': 1,
    'updated_at': _now,
    'device_id': await _deviceId(),
    'deleted_at': null,
    'sync_status': SyncStatus.pending,
  };

  /// La version part de la base et non de [item], qui peut être périmé.
  /// Renvoie `false` si la ligne n'existe pas ou est supprimée.
  @override
  Future<bool> update(T item) async {
    final id = _requireId(item);
    final deviceId = await _deviceId();
    return (await _db).transaction((txn) async {
      final rows = await txn.query(
        table,
        columns: ['version'],
        where: 'id = ? AND $_baseWhere',
        whereArgs: [id],
      );
      if (rows.isEmpty) return false;

      await txn.update(
        table,
        {
          ...item.toMap(),
          'version': (rows.first['version'] as int? ?? 0) + 1,
          'updated_at': _now,
          'device_id': deviceId,
          'deleted_at': null,
          'sync_status': SyncStatus.pending,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    });
  }

  /// Renvoie `false` si la ligne n'existe pas ou est déjà supprimée.
  @override
  Future<bool> delete(int id) async {
    final now = _now;
    final count = await (await _db).rawUpdate(
      'UPDATE "$table" SET deleted_at = ?, updated_at = ?, device_id = ?, '
      'sync_status = ?, version = COALESCE(version, 0) + 1 '
      'WHERE id = ? AND $_baseWhere',
      [now, now, await _deviceId(), SyncStatus.pending, id],
    );
    return count > 0;
  }
}
