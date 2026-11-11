import 'package:sqflite_common/sqlite_api.dart';

import 'outbox.dart';
import 'sync_status.dart';
import 'sync_tables.dart';

/// Records the changes of the personal mode in the outbox (D16: everything
/// the woman notes is synced, the cycle only if she shares it).
///
/// Called in the same transaction as the write. The outbox keeps which row
/// changed; its data are read from the row when the sync sends it, so the
/// latest version always goes, and a row deleted meanwhile is not sent.
abstract final class LocalChanges {
  /// Meta flag: "Partager mon cycle" (off by default, spec §9).
  static const cycleSharingKey = 'partage_cycle';

  static Future<bool> cycleShared(DatabaseExecutor db) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [cycleSharingKey], limit: 1);
    return rows.isNotEmpty && rows.first['value'] == '1';
  }

  /// A row was created or changed (call after the write).
  static Future<void> saved(DatabaseExecutor db, String table, String id) async {
    final t = SyncTables.byName(table);
    if (t == null) return;
    if (t.cycle && !await cycleShared(db)) return;
    final rows = await db.query(table, columns: ['version', 'sync_status'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final status = SyncStatus.parse(rows.first['sync_status']);
    final queued = await Outbox.hasPendingFor(db, table, id);
    // Never reached the server: it is (still) a creation.
    final known = queued || status == SyncStatus.synced || status == SyncStatus.conflict;
    await Outbox.enqueue(
      db,
      table: table,
      operation: known ? 'update' : 'create',
      rowId: id,
      version: rows.first['version'] as int?,
    );
    await db.update(table, {'sync_status': SyncStatus.pending.name}, where: 'id = ?', whereArgs: [id]);
  }

  /// A row is about to be deleted (call before the delete).
  static Future<void> deleting(DatabaseExecutor db, String table, String id) async {
    final t = SyncTables.byName(table);
    if (t == null) return;
    final rows = await db.query(table, columns: ['version', 'sync_status'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final status = SyncStatus.parse(rows.first['sync_status']);
    final queued = await Outbox.hasPendingFor(db, table, id);
    if (!queued && status == SyncStatus.saved) return; // the server never had it
    await Outbox.enqueue(
      db,
      table: table,
      operation: 'delete',
      rowId: id,
      version: rows.first['version'] as int?,
    );
  }

  /// Rows the server does not have yet, queued as creations, parents first:
  /// the whole history of a profile at its first sync, or the cycle once
  /// she starts sharing it. Returns the number of rows queued.
  static Future<int> queueHistory(
    DatabaseExecutor db, {
    required bool includeCycle,
    bool onlyCycle = false,
  }) async {
    var n = 0;
    for (final t in SyncTables.personalWritable) {
      if (t.cycle ? !includeCycle : onlyCycle) continue;
      final rows = await db.query(
        t.name,
        columns: ['id'],
        where: "sync_status IN ('saved', 'pending') AND id IS NOT NULL",
      );
      for (final r in rows) {
        final id = r['id']! as String;
        if (await Outbox.hasPendingFor(db, t.name, id)) continue;
        await Outbox.enqueue(db, table: t.name, operation: 'create', rowId: id);
        await db.update(t.name, {'sync_status': SyncStatus.pending.name}, where: 'id = ?', whereArgs: [id]);
        n++;
      }
    }
    return n;
  }

  /// She stopped sharing her cycle: nothing of it is sent any more, and the
  /// server erases its copy. Her rows are back to "on this phone only".
  static Future<void> stopCycle(DatabaseExecutor db) async {
    final names = [
      for (final t in SyncTables.personalWritable)
        if (t.cycle) t.name,
    ];
    await Outbox.removeTables(db, names);
    for (final name in names) {
      await db.update(name, {'sync_status': SyncStatus.saved.name, 'version': 1});
    }
  }
}
