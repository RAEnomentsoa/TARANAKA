import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/util/clock.dart';
import '../../../core/util/ids.dart';
import '../domain/pregnancy.dart';

class Pregnancy {
  const Pregnancy({
    required this.id,
    required this.dates,
    required this.dueDate,
    this.breastfeeding,
    required this.syncStatus,
  });

  final String id;
  final PregnancyDates dates;
  final DateTime? dueDate;
  final String? breastfeeding;
  final SyncStatus syncStatus;

  bool get delivered => dates.deliveredOn != null;
}

class FollowUpEntry {
  const FollowUpEntry({required this.id, required this.date, this.weightKg, this.notes = ''});
  final String id;
  final DateTime date;
  final double? weightKg;
  final String notes;
}

/// Local store of "Ma grossesse" (encrypted profile database).
class PregnancyRepository {
  PregnancyRepository(this.database, {Clock? clock}) : _clock = clock ?? const SystemClock();

  final AppDatabase database;
  final Clock _clock;
  Database get _db => database.db;
  String _now() => _clock.now().toUtc().toIso8601String();

  DateTime? _date(Object? v) => v is String && v.isNotEmpty ? parseIsoDate(v) : null;

  Pregnancy _fromRow(Map<String, Object?> r) => Pregnancy(
    id: r['id']! as String,
    dates: PregnancyDates(
      lmp: _date(r['ddr']),
      confirmedOn: _date(r['terme_confirme_date']),
      confirmedAgeDays: r['terme_confirme_jours'] as int?,
      deliveredOn: _date(r['date_accouchement']),
    ),
    dueDate: _date(r['dpa']),
    breastfeeding: r['mode_allaitement'] as String?,
    syncStatus: SyncStatus.parse(r['sync_status']),
  );

  /// The current pregnancy (or the last one, during the post-partum).
  Future<Pregnancy?> current() async {
    final rows = await _db.query('grossesse', where: 'terminee = 0', orderBy: 'created_at DESC', limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<Pregnancy> start(PregnancyDates dates, PregnancyCalculator calc) async {
    final id = newUuid();
    final due = calc.dueDate(dates);
    await _db.insert('grossesse', {
      'id': id,
      'ddr': dates.lmp == null ? null : isoDate(dates.lmp!),
      'terme_confirme_date': dates.confirmedOn == null ? null : isoDate(dates.confirmedOn!),
      'terme_confirme_jours': dates.confirmedAgeDays,
      'dpa': due == null ? null : isoDate(due),
      'sync_status': SyncStatus.saved.name,
      'created_at': _now(),
      'updated_at': _now(),
    });
    return (await current())!;
  }

  Future<void> updateDates(String id, PregnancyDates dates, PregnancyCalculator calc) async {
    final due = calc.dueDate(dates);
    await _db.update(
      'grossesse',
      {
        'ddr': dates.lmp == null ? null : isoDate(dates.lmp!),
        'terme_confirme_date': dates.confirmedOn == null ? null : isoDate(dates.confirmedOn!),
        'terme_confirme_jours': dates.confirmedAgeDays,
        'dpa': due == null ? null : isoDate(due),
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> recordDelivery(String id, DateTime on, String breastfeeding) => _db.update(
    'grossesse',
    {'date_accouchement': isoDate(on), 'mode_allaitement': breastfeeding, 'updated_at': _now()},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Closes the pregnancy (e.g. after the post-partum, or to start a new one).
  Future<void> close(String id) =>
      _db.update('grossesse', {'terminee': 1, 'updated_at': _now()}, where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------- contacts

  Future<Map<int, DateTime>> contactsDone(String id, String type) async => {
    for (final r in await _db.query(
      'contact_soin',
      where: 'grossesse_id = ? AND type = ?',
      whereArgs: [id, type],
    ))
      r['numero']! as int: parseIsoDate(r['date_faite']! as String),
  };

  /// "J'y suis allée".
  Future<void> markContact(String id, String type, int number, DateTime on) => _db.insert('contact_soin', {
    'grossesse_id': id,
    'type': type,
    'numero': number,
    'date_faite': isoDate(on),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> unmarkContact(String id, String type, int number) => _db.delete(
    'contact_soin',
    where: 'grossesse_id = ? AND type = ? AND numero = ?',
    whereArgs: [id, type, number],
  );

  // ------------------------------------------------------------ follow-up

  Future<List<FollowUpEntry>> followUps(String id) async =>
      (await _db.query(
            'suivi_grossesse',
            where: 'grossesse_id = ?',
            whereArgs: [id],
            orderBy: 'date_jour DESC, created_at DESC',
          ))
          .map(
            (r) => FollowUpEntry(
              id: r['id']! as String,
              date: parseIsoDate(r['date_jour']! as String),
              weightKg: (r['poids_kg'] as num?)?.toDouble(),
              notes: r['notes']! as String,
            ),
          )
          .toList();

  Future<void> addFollowUp(String id, DateTime on, double? weightKg, String notes) =>
      _db.insert('suivi_grossesse', {
        'id': newUuid(),
        'grossesse_id': id,
        'date_jour': isoDate(on),
        'poids_kg': weightKg,
        'notes': notes.trim(),
        'created_at': _now(),
      });

  Future<void> deleteFollowUp(String entryId) =>
      _db.delete('suivi_grossesse', where: 'id = ?', whereArgs: [entryId]);

  // ------------------------------------------------------------ movements

  Future<Map<DateTime, int>> movements(String id, {int days = 7}) async {
    final from = isoDate(addDays(_clock.now(), -days + 1));
    return {
      for (final r in await _db.query(
        'mouvement_bebe',
        where: 'grossesse_id = ? AND date_jour >= ?',
        whereArgs: [id, from],
        orderBy: 'date_jour DESC',
      ))
        parseIsoDate(r['date_jour']! as String): r['mouvements']! as int,
    };
  }

  Future<void> setMovements(String id, DateTime day, int count) => _db.insert('mouvement_bebe', {
    'grossesse_id': id,
    'date_jour': isoDate(day),
    'mouvements': count,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  // -------------------------------------------------------- danger signals

  /// Kept on the phone (and synced only if the user enabled it).
  Future<void> recordDanger(String id, String code, String period, {SyncStatus status = SyncStatus.saved}) =>
      _db.insert('danger_grossesse', {
        'id': newUuid(),
        'grossesse_id': id,
        'code': code,
        'periode': period,
        'date_signalement': _clock.now().toUtc().toIso8601String(),
        'sync_status': status.name,
        'created_at': _now(),
        'updated_at': _now(),
      });

  Future<List<(String, DateTime)>> dangers(String id) async => [
    for (final r in await _db.query(
      'danger_grossesse',
      where: 'grossesse_id = ?',
      whereArgs: [id],
      orderBy: 'date_signalement DESC',
    ))
      (r['code']! as String, DateTime.parse(r['date_signalement']! as String)),
  ];

  // ---------------------------------------------------------- women's diet

  Future<Set<int>> dietOn(DateTime day) async {
    final rows = await _db.query('alimentation_femme', where: 'date_jour = ?', whereArgs: [isoDate(day)]);
    return rows.isEmpty
        ? <int>{}
        : (jsonDecode(rows.first['groupes']! as String) as List).cast<int>().toSet();
  }

  Future<void> setDiet(DateTime day, Set<int> groups) => _db.insert('alimentation_femme', {
    'date_jour': isoDate(day),
    'groupes': jsonEncode(groups.toList()..sort()),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
