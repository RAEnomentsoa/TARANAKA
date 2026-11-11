import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/db/app_database.dart';
import '../../../core/growth/who_lms.dart';
import '../../../core/sync/local_changes.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/util/clock.dart';
import '../../../core/util/ids.dart';
import '../../agent/domain/models.dart';
import '../../agent/domain/screening.dart';
import '../domain/feeding.dart';
import '../domain/vaccines.dart';

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
    this.others = const {},
  });

  final DateTime date;

  /// `exclusif`, `mixte` or `aucun` (server enum).
  final String breastfeeding;
  final Set<String> foods;
  final int meals;
  final int milkFeeds;

  /// Feeds counted before the feed log existed (kept for those days).
  final int? breastFeeds;

  /// What else a baby under 6 months received ([otherIntakes] codes), when
  /// the feeding was not exclusive.
  final Set<String> others;
}

/// Local store of "Mon enfant". Every change is queued for the sync in the
/// same transaction (D16: the mother's account creates her own children,
/// measurements, feeding logs, feeds and vaccines; see [LocalChanges]).
class ChildRepository {
  ChildRepository(this.database, {Clock? clock}) : _clock = clock ?? const SystemClock();

  final AppDatabase database;
  final Clock _clock;
  Database get _db => database.db;
  String _now() => _clock.now().toUtc().toIso8601String();

  Future<void> _write(String table, String id, Future<void> Function(Transaction txn) change) =>
      _db.transaction((txn) async {
        await change(txn);
        await LocalChanges.saved(txn, table, id);
      });

  Future<void> _remove(String table, String id) => _db.transaction((txn) async {
    await LocalChanges.deleting(txn, table, id);
    await txn.delete(table, where: 'id = ?', whereArgs: [id]);
  });

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
    await _write(
      'enfant',
      id,
      (txn) => txn.insert('enfant', {
        'id': id,
        'nom': name.trim(),
        'sexe': sex,
        'date_naissance': isoDate(birthDate),
        'poids_naissance_kg': birthWeightKg,
        'sync_status': SyncStatus.saved.name,
        'created_at': _now(),
        'updated_at': _now(),
      }),
    );
    return (await child(id))!;
  }

  // ---------------------------------------------------------- custom foods

  static const _customFoodsKey = 'aliments_perso';

  /// Foods typed by the user, for all the children of the profile.
  Future<List<Food>> customFoods() async {
    final raw = await database.getMeta(_customFoodsKey);
    if (raw == null) return const [];
    return [
      for (final f in (jsonDecode(raw) as List).whereType<Map<String, Object?>>())
        if (f['code'] is String && f['groupe'] is int && f['nom'] is String)
          Food.custom(
            code: f['code']! as String,
            group: f['groupe']! as int,
            name: f['nom']! as String,
            hidden: f['masque'] == true,
          ),
    ];
  }

  Future<Food> addCustomFood(int group, String name) async {
    final food = Food.custom(code: 'perso_${newUuid()}', group: group, name: name.trim());
    await _saveCustomFoods([...await customFoods(), food]);
    return food;
  }

  /// Removed from the list, but kept hidden: the days where it was noted
  /// still count its group.
  Future<void> removeCustomFood(String code) async => _saveCustomFoods([
    for (final f in await customFoods())
      f.code == code ? Food.custom(code: f.code, group: f.group, name: f.name, hidden: true) : f,
  ]);

  Future<void> _saveCustomFoods(List<Food> foods) => database.setMeta(
    _customFoodsKey,
    jsonEncode([
      for (final f in foods) {'code': f.code, 'groupe': f.group, 'nom': f.name, if (f.hidden) 'masque': true},
    ]),
  );

  /// The server hides the child's measurements, logs and vaccines with it.
  Future<void> deleteChild(String id) => _remove('enfant', id);

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
    await _write(
      'mesure',
      id,
      (txn) => txn.insert('mesure', {
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
      }),
    );
    return (await growth(child.id)).firstWhere((g) => g.id == id);
  }

  Future<void> deleteGrowth(String id) => _remove('mesure', id);

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
    others: r['autres_recus'] is String
        ? (jsonDecode(r['autres_recus']! as String) as List).cast<String>().toSet()
        : const {},
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
      'autres_recus': jsonEncode([
        for (final c in otherIntakes)
          if (log.others.contains(c)) c,
      ]),
      'updated_at': now,
    };
    final rows = await _db.query(
      'journal_alimentaire',
      columns: ['id'],
      where: 'enfant_id = ? AND date_jour = ?',
      whereArgs: [childId, isoDate(log.date)],
    );
    final id = rows.isEmpty ? newUuid() : rows.first['id']! as String;
    await _write(
      'journal_alimentaire',
      id,
      (txn) => rows.isEmpty
          ? txn.insert('journal_alimentaire', {
              'id': id,
              'enfant_id': childId,
              'date_jour': isoDate(log.date),
              ...values,
              'sync_status': SyncStatus.saved.name,
              'created_at': now,
            })
          : txn.update('journal_alimentaire', values, where: 'id = ?', whereArgs: [id]),
    );
  }

  // ----------------------------------------------------------------- feeds

  /// Feeds of [day] (at the breast or expressed breast milk), by time.
  Future<List<BreastFeed>> feeds(String childId, DateTime day) async {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    return [
      for (final r in await _db.query(
        'tetee',
        where: 'enfant_id = ? AND horodatage >= ? AND horodatage < ?',
        whereArgs: [childId, from.toIso8601String(), to.toIso8601String()],
        orderBy: 'horodatage',
      ))
        BreastFeed(
          id: r['id']! as String,
          at: DateTime.parse(r['horodatage']! as String),
          type: r['type']! as String,
          minutes: r['duree_min'] as int?,
          millilitres: r['quantite_ml'] as int?,
        ),
    ];
  }

  Future<void> addFeed(String childId, DateTime at, String type, {int? minutes, int? millilitres}) {
    final id = newUuid();
    return _write(
      'tetee',
      id,
      (txn) => txn.insert('tetee', {
        'id': id,
        'enfant_id': childId,
        // Local time, without zone: the feeds of a day stay on that day.
        'horodatage': DateTime(at.year, at.month, at.day, at.hour, at.minute).toIso8601String(),
        'type': type,
        'duree_min': minutes,
        'quantite_ml': millilitres,
        'sync_status': SyncStatus.saved.name,
        'created_at': _now(),
        'updated_at': _now(),
      }),
    );
  }

  /// Corrects a feed: its time, type, duration or quantity.
  Future<void> updateFeed(String id, DateTime at, String type, {int? minutes, int? millilitres}) => _write(
    'tetee',
    id,
    (txn) => txn.update(
      'tetee',
      {
        'horodatage': DateTime(at.year, at.month, at.day, at.hour, at.minute).toIso8601String(),
        'type': type,
        'duree_min': minutes,
        'quantite_ml': millilitres,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    ),
  );

  Future<void> deleteFeed(String id) => _remove('tetee', id);

  // ------------------------------------------- breastfeeding difficulties

  static String _difficultiesKey(String childId) => 'allaitement_difficultes_$childId';

  /// Difficulties reported by the mother for this child (codes of
  /// [breastfeedingDifficulties]), kept until she removes them.
  Future<Set<String>> breastfeedingDifficultiesOf(String childId) async {
    final value = (await database.getMetaJson(_difficultiesKey(childId)))?['codes'];
    return value is List ? value.whereType<String>().where(breastfeedingDifficulties.contains).toSet() : {};
  }

  Future<void> setBreastfeedingDifficulties(String childId, Set<String> codes) =>
      database.setMetaJson(_difficultiesKey(childId), {
        'codes': [
          for (final c in breastfeedingDifficulties)
            if (codes.contains(c)) c,
        ],
      });

  // -------------------------------------------------------------- vaccines

  Future<Map<String, DateTime>> vaccinesDone(String childId) async => {
    for (final r in (await vaccineRecords(childId)).values) r.code: r.date,
  };

  /// Each dose received, with where, by whom, and whether the vaccination
  /// card confirms it.
  Future<Map<String, VaccineRecord>> vaccineRecords(String childId) async => {
    for (final r in await _db.query('vaccin_fait', where: 'enfant_id = ?', whereArgs: [childId]))
      r['code']! as String: VaccineRecord(
        code: r['code']! as String,
        date: parseIsoDate(r['date_faite']! as String),
        centre: (r['centre'] as String?) ?? '',
        professional: (r['professionnel'] as String?) ?? '',
        confirmedByCard: switch (r['confirme_carnet']) {
          1 => true,
          0 => false,
          _ => null,
        },
      ),
  };

  Future<void> markVaccine(String childId, String code, DateTime on) =>
      saveVaccine(childId, VaccineRecord(code: code, date: on));

  /// Records a dose (or corrects it: date, centre, professional, card).
  Future<void> saveVaccine(String childId, VaccineRecord r) async {
    final existing = await _db.query(
      'vaccin_fait',
      columns: ['id'],
      where: 'enfant_id = ? AND code = ?',
      whereArgs: [childId, r.code],
    );
    final values = {
      'date_faite': isoDate(r.date),
      'centre': r.centre.trim(),
      'professionnel': r.professional.trim(),
      'confirme_carnet': r.confirmedByCard == null ? null : (r.confirmedByCard! ? 1 : 0),
      'updated_at': _now(),
    };
    // One row per child and dose: a correction keeps the row's id.
    final id = existing.isEmpty ? newUuid() : existing.first['id']! as String;
    await _write(
      'vaccin_fait',
      id,
      (txn) => existing.isEmpty
          ? txn.insert('vaccin_fait', {
              'id': id,
              'enfant_id': childId,
              'code': r.code,
              ...values,
              'sync_status': SyncStatus.saved.name,
              'created_at': _now(),
            })
          : txn.update('vaccin_fait', values, where: 'id = ?', whereArgs: [id]),
    );
  }

  Future<void> unmarkVaccine(String childId, String code) async {
    final rows = await _db.query(
      'vaccin_fait',
      columns: ['id'],
      where: 'enfant_id = ? AND code = ?',
      whereArgs: [childId, code],
    );
    if (rows.isNotEmpty) await _remove('vaccin_fait', rows.first['id']! as String);
  }
}
