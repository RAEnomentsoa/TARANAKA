import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/util/clock.dart';
import '../../../core/util/ids.dart';
import '../domain/pregnancy.dart';
import '../domain/movements.dart';

export '../domain/movements.dart' show MovementEvent, MovementType;

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

/// Who took the measurement: the woman at home, or a health professional
/// (consultation, CPN): shown with every entry of the history.
enum MeasureSource {
  home('domicile'),
  professional('professionnel');

  const MeasureSource(this.code);
  final String code;

  static MeasureSource parse(Object? code) => values.firstWhere((s) => s.code == code, orElse: () => home);
}

/// One dated entry of "Mon suivi": any of the health parameters, and a note.
class FollowUpEntry {
  const FollowUpEntry({
    this.id = '',
    required this.date,
    this.weightKg,
    this.systolic,
    this.diastolic,
    this.fundalHeightCm,
    this.hemoglobinGdl,
    this.glucoseGl,
    this.temperatureC,
    this.notes = '',
    this.source = MeasureSource.home,
    this.glucoseFasting,
  });

  final String id;

  /// Day of the measurement (chosen by the user, today by default).
  final DateTime date;
  final double? weightKg;

  /// Blood pressure, mmHg.
  final int? systolic;
  final int? diastolic;

  /// Fundal height, cm.
  final double? fundalHeightCm;

  /// Haemoglobin, g/dL.
  final double? hemoglobinGdl;

  /// Blood sugar, g/L.
  final double? glucoseGl;
  final double? temperatureC;
  final String notes;
  final MeasureSource source;

  /// Blood sugar taken fasting (null: not said).
  final bool? glucoseFasting;

  bool get isEmpty =>
      weightKg == null &&
      systolic == null &&
      fundalHeightCm == null &&
      hemoglobinGdl == null &&
      glucoseGl == null &&
      temperatureC == null &&
      notes.trim().isEmpty;
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
      dueOn: _date(r['dpa_saisie']),
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
      'dpa_saisie': dates.dueOn == null ? null : isoDate(dates.dueOn!),
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
        'dpa_saisie': dates.dueOn == null ? null : isoDate(dates.dueOn!),
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

  /// Contact dates changed by the user ("Modifier la date"), by number. Kept
  /// in the profile database only, like the rest of the pregnancy.
  Future<Map<int, DateTime>> contactsMoved(String id, String type) async {
    final json = await database.getMetaJson(_movedKey(id, type)) ?? const {};
    return {
      for (final e in json.entries)
        if (int.tryParse(e.key) != null && e.value is String)
          int.parse(e.key): parseIsoDate(e.value! as String),
    };
  }

  /// Sets the date of contact [number], or back to the calendar date ([on] null).
  Future<void> moveContact(String id, String type, int number, DateTime? on) async {
    final moved = {for (final e in (await contactsMoved(id, type)).entries) '${e.key}': isoDate(e.value)};
    on == null ? moved.remove('$number') : moved['$number'] = isoDate(on);
    await database.setMetaJson(_movedKey(id, type), moved.isEmpty ? null : moved);
  }

  static String _movedKey(String id, String type) => 'contacts_deplaces_${type}_$id';

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
              systolic: r['tension_sys'] as int?,
              diastolic: r['tension_dia'] as int?,
              fundalHeightCm: (r['hauteur_uterine_cm'] as num?)?.toDouble(),
              hemoglobinGdl: (r['hemoglobine_g_dl'] as num?)?.toDouble(),
              glucoseGl: (r['glycemie_g_l'] as num?)?.toDouble(),
              temperatureC: (r['temperature_c'] as num?)?.toDouble(),
              notes: r['notes']! as String,
              source: MeasureSource.parse(r['source']),
              glucoseFasting: switch (r['glycemie_a_jeun']) {
                1 => true,
                0 => false,
                _ => null,
              },
            ),
          )
          .toList();

  Future<void> addFollowUp(String id, FollowUpEntry e) => _db.insert('suivi_grossesse', {
    'id': newUuid(),
    'grossesse_id': id,
    ..._followUpRow(e),
    'created_at': _now(),
  });

  /// Corrects an entry (typing mistake): every value is replaced.
  Future<void> updateFollowUp(FollowUpEntry e) => _db.update(
    'suivi_grossesse',
    {..._followUpRow(e), 'updated_at': _now()},
    where: 'id = ?',
    whereArgs: [e.id],
  );

  Map<String, Object?> _followUpRow(FollowUpEntry e) => {
    'date_jour': isoDate(e.date),
    'poids_kg': e.weightKg,
    'tension_sys': e.systolic,
    'tension_dia': e.diastolic,
    'hauteur_uterine_cm': e.fundalHeightCm,
    'hemoglobine_g_dl': e.hemoglobinGdl,
    'glycemie_g_l': e.glucoseGl,
    'glycemie_a_jeun': e.glucoseFasting == null ? null : (e.glucoseFasting! ? 1 : 0),
    'temperature_c': e.temperatureC,
    'notes': e.notes.trim(),
    'source': e.source.code,
  };

  Future<void> deleteFollowUp(String entryId) =>
      _db.delete('suivi_grossesse', where: 'id = ?', whereArgs: [entryId]);

  // ------------------------------------------------------------ movements

  /// Day totals of the former counter ([days] null: the whole pregnancy).
  Future<Map<DateTime, int>> movements(String id, {int? days}) async {
    final from = days == null ? '0000-01-01' : isoDate(addDays(_clock.now(), -days + 1));
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

  /// Movements noted one by one (type, date and time), most recent first
  /// ([days] null: the whole pregnancy).
  Future<List<MovementEvent>> movementEvents(String id, {int? days}) async {
    final from = days == null ? '0000' : dateOnly(addDays(_clock.now(), -days + 1)).toIso8601String();
    return [
      for (final r in await _db.query(
        'mouvement_evenement',
        where: 'grossesse_id = ? AND horodatage >= ?',
        whereArgs: [id, from],
        orderBy: 'horodatage DESC',
      ))
        MovementEvent(
          id: r['id']! as String,
          at: DateTime.parse(r['horodatage']! as String),
          type: MovementType.parse(r['type']),
        ),
    ];
  }

  Future<void> addMovement(String id, DateTime at, MovementType type) => _db.insert('mouvement_evenement', {
    'id': newUuid(),
    'grossesse_id': id,
    // Local time, without zone: the hour the mother felt it.
    'horodatage': DateTime(at.year, at.month, at.day, at.hour, at.minute).toIso8601String(),
    'type': type.code,
    'created_at': _now(),
  });

  Future<void> deleteMovement(String eventId) =>
      _db.delete('mouvement_evenement', where: 'id = ?', whereArgs: [eventId]);

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

/// The current pregnancy with its contacts: done and moved, antenatal and
/// postnatal. Shared by the home of "Ma grossesse" and the contacts screen, so
/// both show the same dates and the same SA.
class PregnancyContacts {
  const PregnancyContacts({
    required this.pregnancy,
    this.ancDone = const {},
    this.pncDone = const {},
    this.ancMoved = const {},
    this.pncMoved = const {},
  });

  final Pregnancy? pregnancy;
  final Map<int, DateTime> ancDone;
  final Map<int, DateTime> pncDone;
  final Map<int, DateTime> ancMoved;
  final Map<int, DateTime> pncMoved;

  static Future<PregnancyContacts> load(PregnancyRepository repo) async {
    final p = await repo.current();
    if (p == null) return const PregnancyContacts(pregnancy: null);
    return PregnancyContacts(
      pregnancy: p,
      ancDone: await repo.contactsDone(p.id, 'cpn'),
      pncDone: await repo.contactsDone(p.id, 'pn'),
      ancMoved: await repo.contactsMoved(p.id, 'cpn'),
      pncMoved: await repo.contactsMoved(p.id, 'pn'),
    );
  }

  List<CareContact> antenatal(PregnancyCalculator calc, DateTime today) =>
      calc.antenatal(pregnancy!.dates, ancDone, today, moved: ancMoved);

  List<CareContact> postnatal(PregnancyCalculator calc, DateTime today) =>
      calc.postnatal(pregnancy!.dates, pncDone, today, moved: pncMoved);
}
