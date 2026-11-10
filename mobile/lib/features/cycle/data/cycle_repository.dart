import 'dart:convert';

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
    symptoms: _symptoms(r['symptomes'] as String?),
    irregular: (r['irreguliere'] as int? ?? 0) == 1,
  );

  static Set<String> _symptoms(String? json) {
    if (json == null || json.isEmpty) return const {};
    final value = jsonDecode(json);
    return value is List ? value.whereType<String>().toSet() : const {};
  }

  static String _symptomsJson(Set<String> s) => jsonEncode([
    for (final code in periodSymptoms)
      if (s.contains(code)) code,
  ]);

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

  /// A period entered afterwards (e.g. three months ago), with its end and,
  /// if noted, its intensity, symptoms and irregularity.
  Future<Period> add(
    DateTime startDay,
    DateTime? endDay, {
    String? intensity,
    Set<String>? symptoms,
    bool? irregular,
  }) async {
    final p = await start(startDay);
    if (endDay != null) await end(p.id, endDay);
    if (intensity != null || symptoms != null || irregular != null) {
      await setDetails(p.id, intensity: intensity, symptoms: symptoms, irregular: irregular);
    }
    return (await periods()).firstWhere((e) => e.id == p.id);
  }

  Future<void> end(String id, DateTime day) async {
    await _update(id, {'date_fin': isoDate(day)});
    await _syncPeriod(id);
  }

  Future<void> setDetails(
    String id, {
    String? intensity,
    int? pain,
    int? mood,
    String? notes,
    Set<String>? symptoms,
    bool? irregular,
  }) => _update(id, {
    'intensite': ?intensity,
    'douleur': ?pain,
    'humeur': ?mood,
    'notes': ?notes,
    if (symptoms != null) 'symptomes': _symptomsJson(symptoms),
    if (irregular != null) 'irreguliere': irregular ? 1 : 0,
  });

  Future<void> setDates(String id, DateTime start, DateTime? end) async {
    await _update(id, {'date_debut': isoDate(start), 'date_fin': end == null ? null : isoDate(end)});
    await _syncPeriod(id);
  }

  // ---- daily follow-up ("Mon suivi du jour"), one row per day

  DayLog _dayFromRow(Map<String, Object?> r) => DayLog(
    day: parseIsoDate(r['date_jour']! as String),
    flow: r['flux'] as String?,
    pain: r['douleur'] as int?,
    mood: r['humeur'] as int?,
    symptoms: _symptoms(r['symptomes'] as String?),
  );

  /// The days noted, most recent first; [from]–[to] included when given.
  Future<List<DayLog>> dayLogs({DateTime? from, DateTime? to}) async {
    final where = [if (from != null) 'date_jour >= ?', if (to != null) 'date_jour <= ?'];
    final rows = await _db.query(
      'cycle_jour',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: [if (from != null) isoDate(from), if (to != null) isoDate(to)],
      orderBy: 'date_jour DESC',
    );
    return rows.map(_dayFromRow).toList();
  }

  Future<DayLog?> dayLog(DateTime day) async {
    final rows = await _db.query('cycle_jour', where: 'date_jour = ?', whereArgs: [isoDate(day)]);
    return rows.isEmpty ? null : _dayFromRow(rows.first);
  }

  /// Saves (or corrects) the follow-up of one day; an empty one is removed.
  /// The period of that day then takes its flow, pain, mood and symptoms.
  Future<void> saveDay(DayLog log) async {
    final day = isoDate(log.day);
    if (log.isEmpty) {
      await _db.delete('cycle_jour', where: 'date_jour = ?', whereArgs: [day]);
    } else {
      final existing = await _db.query(
        'cycle_jour',
        columns: ['created_at'],
        where: 'date_jour = ?',
        whereArgs: [day],
      );
      await _db.insert('cycle_jour', {
        'date_jour': day,
        'flux': log.flow,
        'douleur': log.pain,
        'humeur': log.mood,
        'symptomes': _symptomsJson(log.symptoms),
        'created_at': existing.isEmpty ? _now() : existing.first['created_at'],
        'updated_at': _now(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final period = periodOn(await periods(), log.day, _clock.now());
    if (period != null) await _syncPeriod(period.id);
  }

  Future<void> deleteDay(DateTime day) => saveDay(DayLog(day: day));

  /// A period with daily follow-ups takes from them: the heaviest flow, the
  /// strongest pain, the last mood, every symptom felt. Without any, what was
  /// noted on the period itself stays.
  Future<void> _syncPeriod(String id) async {
    final p = (await periods()).where((e) => e.id == id).firstOrNull;
    if (p == null) return;
    final days = await dayLogs(from: p.start, to: p.end ?? dateOnly(_clock.now()));
    if (days.isEmpty) return;
    final pains = days.map((d) => d.pain).whereType<int>();
    await setDetails(
      id,
      intensity: heaviestFlow(days),
      pain: pains.isEmpty ? null : pains.reduce((a, b) => a > b ? a : b),
      mood: days.map((d) => d.mood).whereType<int>().firstOrNull,
      symptoms: {for (final d in days) ...d.symptoms},
    );
  }

  // ---- settings (profile database only, like the periods)

  static const _settingsKey = 'cycle_settings';

  /// Usual length of a period chosen by the user (3 to 8 days), or null.
  Future<int?> periodDays() async {
    final value = (await database.getMetaJson(_settingsKey))?['duree_regles'];
    return value is num ? value.toInt().clamp(periodDaysMin, periodDaysMax) : null;
  }

  Future<void> setPeriodDays(int days) =>
      database.setMetaJson(_settingsKey, {'duree_regles': days.clamp(periodDaysMin, periodDaysMax)});

  /// Periods whose end was never noted and that cannot still be going on get
  /// their usual length as end, so they no longer run over the whole month.
  Future<void> closeForgotten(DateTime today, int periodDays) async {
    for (final p in await periods()) {
      final end = forgottenEnd(p, today, periodDays);
      if (end != null) await this.end(p.id, end);
    }
  }

  /// Start of the most recent period, e.g. to date a pregnancy.
  Future<DateTime?> lastPeriodStart() async {
    final rows = await _db.query('cycle', columns: ['date_debut'], orderBy: 'date_debut DESC', limit: 1);
    return rows.isEmpty ? null : parseIsoDate(rows.first['date_debut']! as String);
  }

  Future<void> delete(String id) => _db.delete('cycle', where: 'id = ?', whereArgs: [id]);

  Future<void> _update(String id, Map<String, Object?> values) =>
      _db.update('cycle', {...values, 'updated_at': _now()}, where: 'id = ?', whereArgs: [id]);
}
