import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../util/ids.dart';

class OutboxOp {
  OutboxOp({
    required this.seq,
    required this.key,
    required this.table,
    required this.operation,
    required this.rowId,
    required this.version,
    required this.payload,
    required this.attempts,
    this.lastStatus,
    this.lastError,
  });

  final int seq;

  /// `cle_idempotence`: the same key always gets the same answer (spec §9).
  final String key;
  final String table;

  /// create | update | delete
  final String operation;
  final String rowId;
  final int? version;
  final Map<String, Object?> payload;
  final int attempts;
  final String? lastStatus;
  final String? lastError;

  OutboxOp withPayload(Map<String, Object?> value) => OutboxOp(
    seq: seq,
    key: key,
    table: table,
    operation: operation,
    rowId: rowId,
    version: version,
    payload: value,
    attempts: attempts,
    lastStatus: lastStatus,
    lastError: lastError,
  );

  /// One operation of `POST /api/sync/push/`.
  Map<String, Object?> toPush() => {
    'cle_idempotence': key,
    'table': table,
    'operation': operation,
    'id': rowId,
    if (operation != 'create' && version != null) 'version': version,
    if (operation != 'delete') 'donnees': payload,
  };

  static OutboxOp fromRow(Map<String, Object?> r) => OutboxOp(
    seq: r['seq']! as int,
    key: r['cle_idempotence']! as String,
    table: r['table_name']! as String,
    operation: r['operation']! as String,
    rowId: r['row_id']! as String,
    version: r['version'] as int?,
    payload: (jsonDecode(r['payload']! as String) as Map).cast<String, Object?>(),
    attempts: r['attempts']! as int,
    lastStatus: r['last_status'] as String?,
    lastError: r['last_error'] as String?,
  );
}

/// Outbox (spec §9): every change is written locally and queued in the same
/// transaction, then sent in order by the sync.
abstract final class Outbox {
  /// Queues a change. A change to a row whose previous change was never sent
  /// is merged into it (one operation, one key), so a create followed by an
  /// edit before the sync is still a single create.
  static Future<void> enqueue(
    DatabaseExecutor db, {
    required String table,
    required String operation,
    required String rowId,
    int? version,
    Map<String, Object?> payload = const {},
    DateTime? now,
  }) async {
    final waiting = await db.query(
      'outbox',
      where: 'table_name = ? AND row_id = ? AND attempts = 0',
      whereArgs: [table, rowId],
      orderBy: 'seq DESC',
      limit: 1,
    );
    if (waiting.isNotEmpty) {
      final previous = OutboxOp.fromRow(waiting.first);
      if (operation == 'delete' && previous.operation == 'create') {
        // Never reached the server: nothing to send at all.
        await db.delete('outbox', where: 'seq = ?', whereArgs: [previous.seq]);
        return;
      }
      if (operation == 'update' && previous.operation != 'delete') {
        await db.update(
          'outbox',
          {
            'payload': jsonEncode({...previous.payload, ...payload}),
          },
          where: 'seq = ?',
          whereArgs: [previous.seq],
        );
        return;
      }
    }
    await db.insert('outbox', {
      'cle_idempotence': newUuid(),
      'table_name': table,
      'operation': operation,
      'row_id': rowId,
      'version': version,
      'payload': jsonEncode(payload),
      'created_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  static Future<List<OutboxOp>> pending(DatabaseExecutor db, {int limit = 100}) async =>
      (await db.query('outbox', orderBy: 'seq', limit: limit)).map(OutboxOp.fromRow).toList();

  static Future<int> count(DatabaseExecutor db) async =>
      (await db.rawQuery('SELECT count(*) AS n FROM outbox')).first['n']! as int;

  /// Operations the server refused last time (shown as an error).
  static Future<int> failedCount(DatabaseExecutor db) async =>
      (await db.rawQuery('SELECT count(*) AS n FROM outbox WHERE last_status IS NOT NULL')).first['n']!
          as int;

  /// Drops the queued operations of [tables] (e.g. the cycle, once she stops
  /// sharing it).
  static Future<void> removeTables(DatabaseExecutor db, List<String> tables) => db.delete(
    'outbox',
    where: 'table_name IN (${List.filled(tables.length, '?').join(',')})',
    whereArgs: tables,
  );

  static Future<bool> hasPendingFor(DatabaseExecutor db, String table, String rowId) async => (await db.query(
    'outbox',
    where: 'table_name = ? AND row_id = ?',
    whereArgs: [table, rowId],
    limit: 1,
  )).isNotEmpty;

  /// Marks operations as being sent: later edits get their own operation.
  static Future<void> markSending(DatabaseExecutor db, List<int> seqs) => db.rawUpdate(
    'UPDATE outbox SET attempts = attempts + 1 WHERE seq IN (${List.filled(seqs.length, '?').join(',')})',
    seqs,
  );

  static Future<void> remove(DatabaseExecutor db, int seq) =>
      db.delete('outbox', where: 'seq = ?', whereArgs: [seq]);

  static Future<void> recordFailure(DatabaseExecutor db, int seq, String status, String? error) =>
      db.update('outbox', {'last_status': status, 'last_error': error}, where: 'seq = ?', whereArgs: [seq]);

  /// After the server applied a change and answered with its new version,
  /// later queued edits of the same row carry that version (they were made
  /// on top of it on this phone).
  static Future<void> carryVersion(DatabaseExecutor db, String table, String rowId, int version) => db.update(
    'outbox',
    {'version': version},
    where: "table_name = ? AND row_id = ? AND operation != 'create'",
    whereArgs: [table, rowId],
  );

  static Future<void> replacePayloadField(DatabaseExecutor db, int seq, String field, Object? value) async {
    final rows = await db.query('outbox', where: 'seq = ?', whereArgs: [seq]);
    if (rows.isEmpty) return;
    final op = OutboxOp.fromRow(rows.first);
    await db.update(
      'outbox',
      {
        'payload': jsonEncode({...op.payload, field: value}),
      },
      where: 'seq = ?',
      whereArgs: [seq],
    );
  }
}
