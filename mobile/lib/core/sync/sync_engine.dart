import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../config/config_repository.dart';
import '../db/app_database.dart';
import 'api_client.dart';
import 'outbox.dart';
import 'sync_status.dart';

/// How one server table maps to its local table.
class TableAdapter {
  const TableAdapter({required this.serverTable, required this.localTable, required this.toLocal});

  final String serverTable;
  final String localTable;

  /// Server row (as in `/sync/pull/` and push answers) → local columns.
  final Map<String, Object?> Function(Map<String, Object?> server) toLocal;
}

class SyncReport {
  int sent = 0;
  int applied = 0;
  int conflicts = 0;
  int failed = 0;
  int received = 0;
  bool configUpdated = false;
  final List<String> errors = [];

  @override
  String toString() =>
      'SyncReport(sent $sent, applied $applied, conflicts $conflicts, failed $failed, received $received)';
}

/// Called when the server refuses an operation, to let the feature fix it
/// (e.g. a referral code already used). Return true if the op was changed and
/// can be retried.
typedef ErrorFixer = Future<bool> Function(DatabaseExecutor db, OutboxOp op, Object? errors);

/// Outbox push then incremental pull (spec §9).
///
/// - Operations are sent in order, by batches of at most 100, at most one per
///   row in a batch (a second edit waits for the new version of the first).
/// - `applique` / `deja_applique` → Synchronisé, with the server's row.
/// - `conflit` → Conflit: the local version is kept and nothing is
///   overwritten until a person decides on the web.
/// - `erreur` / `refuse` / `introuvable` → stays "À synchroniser", with the
///   reason, and is retried next time (the server stores no error answer).
/// - Pull: per table, from a saved cursor; rows with local changes waiting or
///   an open conflict are not overwritten; deleted rows are removed.
class SyncEngine {
  SyncEngine({
    required this.database,
    required this.api,
    required this.adapters,
    this.config,
    this.fixers = const {},
  });

  final AppDatabase database;
  final ApiClient api;
  final List<TableAdapter> adapters;
  final ConfigRepository? config;
  final Map<String, ErrorFixer> fixers;

  Database get _db => database.db;

  TableAdapter? _adapter(String serverTable) {
    for (final a in adapters) {
      if (a.serverTable == serverTable) return a;
    }
    return null;
  }

  Future<SyncReport> run({bool pull = true}) async {
    final report = SyncReport();
    await push(report);
    if (pull) await this.pull(report);
    await database.setMeta('last_sync', DateTime.now().toUtc().toIso8601String());
    return report;
  }

  Future<void> push(SyncReport report) async {
    for (var round = 0; round < 50; round++) {
      final waiting = await Outbox.pending(_db, limit: 500);
      if (waiting.isEmpty) return;
      final batch = <OutboxOp>[];
      final rows = <String>{};
      for (final op in waiting) {
        if (batch.length == 100) break;
        if (rows.add('${op.table}/${op.rowId}')) batch.add(op);
      }
      await Outbox.markSending(_db, batch.map((o) => o.seq).toList());
      report.sent += batch.length;
      final answer = await api.push(batch.map((o) => o.toPush()).toList());
      final results = {
        for (final r in (answer['resultats']! as List).cast<Map<Object?, Object?>>())
          r['cle_idempotence']: r.cast<String, Object?>(),
      };
      var progress = false;
      for (final op in batch) {
        final r = results[op.key];
        if (r == null) continue;
        progress |= await _handle(op, r, report);
      }
      if (!progress) return;
    }
  }

  Future<bool> _handle(OutboxOp op, Map<String, Object?> r, SyncReport report) async {
    final adapter = _adapter(op.table);
    final status = r['statut'] as String?;
    final ligne = (r['ligne'] as Map?)?.cast<String, Object?>();
    switch (status) {
      case 'applique' || 'deja_applique':
        report.applied++;
        await _db.transaction((txn) async {
          await Outbox.remove(txn, op.seq);
          if (op.operation == 'delete' || adapter == null) return;
          if (ligne != null) {
            final version = ligne['version'] as int?;
            if (version != null) await Outbox.carryVersion(txn, op.table, op.rowId, version);
            final stillWaiting = await Outbox.hasPendingFor(txn, op.table, op.rowId);
            final local = adapter.toLocal(ligne);
            if (stillWaiting) {
              // Keep local edits; take the new version and server-computed fields only.
              await txn.update(
                adapter.localTable,
                {'version': version},
                where: 'id = ?',
                whereArgs: [op.rowId],
              );
            } else {
              await _upsert(txn, adapter, {...local, 'sync_status': SyncStatus.synced.name});
            }
          } else {
            await txn.update(
              adapter.localTable,
              {'sync_status': SyncStatus.synced.name},
              where: 'id = ?',
              whereArgs: [op.rowId],
            );
          }
        });
        return true;
      case 'conflit':
        report.conflicts++;
        await _db.transaction((txn) async {
          await Outbox.remove(txn, op.seq);
          final conflictId = r['conflit_id'] as String?;
          if (conflictId != null) {
            await txn.insert('conflit', {
              'id': conflictId,
              'table_name': op.table,
              'ligne_id': op.rowId,
              'statut': 'a_verifier',
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          if (adapter != null) {
            await txn.update(
              adapter.localTable,
              {'sync_status': SyncStatus.conflict.name},
              where: 'id = ?',
              whereArgs: [op.rowId],
            );
          }
        });
        return true;
      default:
        report.failed++;
        final errors = r['erreurs'];
        final fixer = fixers[op.table];
        var fixed = false;
        await _db.transaction((txn) async {
          await Outbox.recordFailure(txn, op.seq, status ?? 'erreur', jsonEncode(errors));
          if (fixer != null) fixed = await fixer(txn, op, errors);
          // Back to "not sent": it is retried with the next sync.
          await txn.update('outbox', {'attempts': 0}, where: 'seq = ?', whereArgs: [op.seq]);
        });
        report.errors.add('${op.table}/${op.operation}: $status ${jsonEncode(errors)}');
        return fixed;
    }
  }

  Future<void> pull(SyncReport report) async {
    var configVersion = config?.isLoaded == true ? config!.current.version : null;
    for (final adapter in adapters) {
      for (var page = 0; page < 200; page++) {
        final cursor = await database.getMetaJson('pull_${adapter.serverTable}');
        final answer = await api.pull(
          tables: [adapter.serverTable],
          since: cursor?['depuis'] as String?,
          afterId: cursor?['apres_id'] as String?,
          configVersion: configVersion,
        );
        await _applyConflicts(answer['conflits']);
        final cfg = (answer['config_clinique'] as Map?)?.cast<String, Object?>();
        final update = (cfg?['mise_a_jour'] as Map?)?.cast<String, Object?>();
        if (update != null && config != null && await config!.applyUpdate(update)) {
          report.configUpdated = true;
        }
        configVersion = null;
        final table = ((answer['tables']! as Map)[adapter.serverTable] as Map?)?.cast<String, Object?>();
        if (table == null) break; // not readable by this profile
        final lines = (table['lignes']! as List).cast<Map<Object?, Object?>>();
        await _db.transaction((txn) async {
          for (final raw in lines) {
            final line = raw.cast<String, Object?>();
            final id = line['id']! as String;
            if (await Outbox.hasPendingFor(txn, adapter.serverTable, id)) continue;
            if (await _openConflict(txn, id)) continue;
            if (line['deleted_at'] != null) {
              await txn.delete(adapter.localTable, where: 'id = ?', whereArgs: [id]);
            } else {
              try {
                await _upsert(txn, adapter, {
                  ...adapter.toLocal(line),
                  'sync_status': SyncStatus.synced.name,
                });
              } on DatabaseException {
                // A row whose parent this phone can't see: skipped.
                continue;
              }
            }
            report.received++;
          }
          await txn.insert('meta', {
            'key': 'pull_${adapter.serverTable}',
            'value': jsonEncode({'depuis': table['prochain_depuis'], 'apres_id': table['apres_id']}),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        });
        if (table['suite'] != true) break;
      }
    }
  }

  Future<bool> _openConflict(DatabaseExecutor txn, String rowId) async => (await txn.query(
    'conflit',
    where: "ligne_id = ? AND statut = 'a_verifier'",
    whereArgs: [rowId],
    limit: 1,
  )).isNotEmpty;

  Future<void> _applyConflicts(Object? conflicts) async {
    if (conflicts is! List || conflicts.isEmpty) return;
    await _db.transaction((txn) async {
      for (final c in conflicts.cast<Map<Object?, Object?>>()) {
        await txn.insert('conflit', {
          'id': c['id'],
          'table_name': c['table_nom'],
          'ligne_id': c['ligne_id'],
          'statut': c['statut'],
          'resolution': c['resolution'],
          'updated_at': c['resolu_le'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Update, else insert. Never REPLACE: it would delete the row first and
  /// cascade to its children.
  static Future<void> _upsert(DatabaseExecutor txn, TableAdapter adapter, Map<String, Object?> values) async {
    final id = values['id'];
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await txn.update(adapter.localTable, values, where: 'id = ?', whereArgs: [id]);
    if (count == 0) {
      await txn.insert(adapter.localTable, {'created_at': now, 'updated_at': now, ...values});
    }
  }
}
