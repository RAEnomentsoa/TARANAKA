import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/util/clock.dart';
import '../../../core/util/ids.dart';
import '../domain/cycle.dart';

/// Local store of "Mon cycle" (spec §4: stored only on the phone by default,
/// never synced without explicit activation). Nothing here touches the outbox.
class CycleRepository {
  CycleRepository(this.database, {Clock? clock}) : _clock = clock ?? const SystemClock();

  final AppDatabase database;
  final Clock _clock;
  Database get _db => database.db;
  String _now() => _clock.now().toUtc().toIso8601String();

  Period _fromRow(Map<String, Object?> r) => Period(
    id: r['id']! as String,
    start: parseIsoDate(r['date_debut']! as String),
    end: r['date_fin'] == null ? null : parseIsoDate(r['date_fin']! as String),
    intensity: r['intensite']! as String,
    pain: r['douleur']! as int,
    mood: r['humeur'] as int?,
    notes: r['notes']! as String,
  );

  Future<List<Period>> periods() async =>
      (await _db.query('cycle', orderBy: 'date_debut DESC')).map(_fromRow).toList();

  /// "Mes règles ont commencé aujourd'hui" (one tap).
  Future<Period> start(DateTime day) async {
    final id = newUuid();
    await _db.insert('cycle', {
      'id': id,
      'date_debut': isoDate(day),
      'sync_status': SyncStatus.saved.name,
      'created_at': _now(),
      'updated_at': _now(),
    });
    return (await periods()).firstWhere((p) => p.id == id);
  }

  /// A period entered afterwards (e.g. three months ago), with its end.
  Future<Period> add(DateTime startDay, DateTime? endDay) async {
    final p = await start(startDay);
    if (endDay == null) return p;
    await end(p.id, endDay);
    return (await periods()).firstWhere((e) => e.id == p.id);
  }

  Future<void> end(String id, DateTime day) => _update(id, {'date_fin': isoDate(day)});

  Future<void> setDetails(String id, {String? intensity, int? pain, int? mood, String? notes}) =>
      _update(id, {'intensite': ?intensity, 'douleur': ?pain, 'humeur': ?mood, 'notes': ?notes});

  Future<void> setDates(String id, DateTime start, DateTime? end) =>
      _update(id, {'date_debut': isoDate(start), 'date_fin': end == null ? null : isoDate(end)});

  Future<void> delete(String id) => _db.delete('cycle', where: 'id = ?', whereArgs: [id]);

  Future<void> _update(String id, Map<String, Object?> values) =>
      _db.update('cycle', {...values, 'updated_at': _now()}, where: 'id = ?', whereArgs: [id]);
}
