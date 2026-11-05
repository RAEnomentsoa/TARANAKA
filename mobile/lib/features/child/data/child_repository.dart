import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/db/app_database.dart';
import '../../../core/growth/who_lms.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/util/clock.dart';
import '../../../core/util/ids.dart';
import '../../agent/domain/models.dart';
import '../../agent/domain/screening.dart';

/// A child followed by a parent (personal mode).
class MyChild {
  const MyChild(this.child, this.birthWeightKg);
  final Child child;
  final double? birthWeightKg;

  String get id => child.id;
  String get name => child.name;
  String get sex => child.sex;
  DateTime get birthDate => child.birthDate;
}

class GrowthEntry {
  const GrowthEntry({
    required this.id,
    required this.date,
    required this.ageDays,
    required this.weightKg,
    required this.lengthCm,
    required this.position,
    required this.correctedLengthCm,
    required this.z,
  });

  final String id;
  final DateTime date;
  final int ageDays;
  final double weightKg;
  final double lengthCm;
  final String position;
  final double correctedLengthCm;
  final ZScores z;
}

class FeedingLog {
  const FeedingLog({
    required this.date,
    required this.breastfeeding,
    required this.foods,
    required this.meals,
    required this.milkFeeds,
    this.breastFeeds,
  });

  final DateTime date;

  /// `exclusif`, `mixte` or `aucun` (server enum).
  final String breastfeeding;
  final Set<String> foods;
  final int meals;
  final int milkFeeds;
  final int? breastFeeds;
}

/// Local store of "Mon enfant". Rows stay "Enregistré" on the phone: the
/// server can't receive them from a parent (docs/API_ISSUES.md M1).
class ChildRepository {
  ChildRepository(this.database, {Clock? clock}) : _clock = clock ?? const SystemClock();

  final AppDatabase database;
  final Clock _clock;
  Database get _db => database.db;
  String _now() => _clock.now().toUtc().toIso8601String();

  Future<List<MyChild>> children() async => (await _db.query(
    'enfant',
    orderBy: 'date_naissance DESC',
  )).map((r) => MyChild(Child.fromRow(r), (r['poids_naissance_kg'] as num?)?.toDouble())).toList();

  Future<MyChild?> child(String id) async {
    final rows = await _db.query('enfant', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return MyChild(Child.fromRow(rows.first), (rows.first['poids_naissance_kg'] as num?)?.toDouble());
  }

  Future<MyChild> addChild({
    required String name,
    required String sex,
    required DateTime birthDate,
    double? birthWeightKg,
  }) async {
    final id = newUuid();
    await _db.insert('enfant', {
      'id': id,
      'nom': name.trim(),
      'sexe': sex,
      'date_naissance': isoDate(birthDate),
      'poids_naissance_kg': birthWeightKg,
      'sync_status': SyncStatus.saved.name,
      'created_at': _now(),
      'updated_at': _now(),
    });
    return (await child(id))!;
  }

  Future<void> deleteChild(String id) => _db.delete('enfant', where: 'id = ?', whereArgs: [id]);

  // ---------------------------------------------------------------- growth

  Future<List<GrowthEntry>> growth(String childId) async =>
      (await _db.query('mesure', where: 'enfant_id = ?', whereArgs: [childId], orderBy: 'date_mesure'))
          .map(
            (r) => GrowthEntry(
              id: r['id']! as String,
              date: parseIsoDate(r['date_mesure']! as String),
              ageDays: (r['age_jour'] as int?) ?? 0,
              weightKg: (r['poids_kg']! as num).toDouble(),
              lengthCm: (r['taille_cm']! as num).toDouble(),
              position: r['position']! as String,
              correctedLengthCm: ((r['taille_corrigee_cm'] ?? r['taille_cm'])! as num).toDouble(),
              z: ZScores(
                waz: (r['waz'] as num?)?.toDouble(),
                haz: (r['haz'] as num?)?.toDouble(),
                whz: (r['whz'] as num?)?.toDouble(),
              ),
            ),
          )
          .toList();

  Future<GrowthEntry> addGrowth({
    required MyChild child,
    required DateTime date,
    required double weightKg,
    required double lengthCm,
    required String position,
    required WhoTables tables,
    required String alerte,
  }) async {
    final id = newUuid();
    final ageDays = ScreeningCalculator.ageDays(child.birthDate, date);
    final corrected = ScreeningCalculator.correctedLength(lengthCm, position, ageDays);
    final z = GrowthMath.compute(
      tables,
      sex: child.sex,
      ageDays: ageDays,
      weightKg: weightKg,
      correctedLengthCm: corrected,
    );
    await _db.insert('mesure', {
      'id': id,
      'enfant_id': child.id,
      'date_mesure': isoDate(date),
      'poids_kg': weightKg,
      'taille_cm': lengthCm,
      'position': position,
      'age_jour': ageDays,
      'age_mois': ScreeningCalculator.ageMonths(ageDays),
      'taille_corrigee_cm': corrected,
      'waz': z.waz,
      'haz': z.haz,
      'whz': z.whz,
      'alerte': alerte,
      'sync_status': SyncStatus.saved.name,
      'created_at': _now(),
      'updated_at': _now(),
    });
    return (await growth(child.id)).firstWhere((g) => g.id == id);
  }

  Future<void> deleteGrowth(String id) => _db.delete('mesure', where: 'id = ?', whereArgs: [id]);

  // --------------------------------------------------------------- feeding

  Future<FeedingLog?> feeding(String childId, DateTime day) async {
    final rows = await _db.query(
      'journal_alimentaire',
      where: 'enfant_id = ? AND date_jour = ?',
      whereArgs: [childId, isoDate(day)],
    );
    return rows.isEmpty ? null : _log(rows.first);
  }

  Future<List<FeedingLog>> feedingSince(String childId, DateTime from) async => (await _db.query(
    'journal_alimentaire',
    where: 'enfant_id = ? AND date_jour >= ?',
    whereArgs: [childId, isoDate(from)],
    orderBy: 'date_jour DESC',
  )).map(_log).toList();

  FeedingLog _log(Map<String, Object?> r) => FeedingLog(
    date: parseIsoDate(r['date_jour']! as String),
    breastfeeding: r['type_allaitement']! as String,
    foods: (jsonDecode(r['aliments']! as String) as List).cast<String>().toSet(),
    meals: r['repas']! as int,
    milkFeeds: r['laits']! as int,
    breastFeeds: r['tetees'] as int?,
  );

  /// One row per child and day; saving again replaces the day.
  Future<void> saveFeeding(String childId, FeedingLog log) async {
    final now = _now();
    final values = {
      'type_allaitement': log.breastfeeding,
      'aliments': jsonEncode(log.foods.toList()..sort()),
      'repas': log.meals,
      'laits': log.milkFeeds,
      'tetees': log.breastFeeds,
      'updated_at': now,
    };
    final updated = await _db.update(
      'journal_alimentaire',
      values,
      where: 'enfant_id = ? AND date_jour = ?',
      whereArgs: [childId, isoDate(log.date)],
    );
    if (updated == 0) {
      await _db.insert('journal_alimentaire', {
        'id': newUuid(),
        'enfant_id': childId,
        'date_jour': isoDate(log.date),
        ...values,
        'sync_status': SyncStatus.saved.name,
        'created_at': now,
      });
    }
  }

  // -------------------------------------------------------------- vaccines

  Future<Map<String, DateTime>> vaccinesDone(String childId) async => {
    for (final r in await _db.query('vaccin_fait', where: 'enfant_id = ?', whereArgs: [childId]))
      r['code']! as String: parseIsoDate(r['date_faite']! as String),
  };

  Future<void> markVaccine(String childId, String code, DateTime on) => _db.insert('vaccin_fait', {
    'enfant_id': childId,
    'code': code,
    'date_faite': isoDate(on),
    'created_at': _now(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> unmarkVaccine(String childId, String code) =>
      _db.delete('vaccin_fait', where: 'enfant_id = ? AND code = ?', whereArgs: [childId, code]);
}
