import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/outbox.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/util/clock.dart';
import '../../../core/util/ids.dart';
import '../domain/models.dart';
import '../domain/referral_code.dart';
import '../domain/screening.dart';

/// Local store of the agent mode. Every write goes with its outbox operation
/// in one transaction: nothing is lost if the phone stops in between.
class AgentRepository {
  AgentRepository(this.database, this.codes, {Clock? clock}) : _clock = clock ?? const SystemClock();

  final AppDatabase database;
  final ReferralCodeGenerator codes;
  final Clock _clock;

  Database get _db => database.db;
  String _now() => _clock.now().toUtc().toIso8601String();

  // ---------------------------------------------------------------- children

  Future<List<Child>> children({String search = ''}) async {
    final q = search.trim().toLowerCase();
    final rows = await _db.query(
      'enfant',
      where: q.isEmpty ? null : 'lower(nom) LIKE ?',
      whereArgs: q.isEmpty ? null : ['%$q%'],
      orderBy: 'nom COLLATE NOCASE',
    );
    return rows.map(Child.fromRow).toList();
  }

  Future<Child?> child(String id) async {
    final rows = await _db.query('enfant', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Child.fromRow(rows.first);
  }

  Future<Child> createChild({
    required String name,
    required String sex,
    required DateTime birthDate,
    required int? regionId,
    required String agentId,
  }) async {
    final id = newUuid();
    final now = _now();
    final payload = {
      'nom': name.trim(),
      'sexe': sex,
      'date_naissance': isoDate(birthDate),
      'region_id': regionId,
      'asc_id': agentId,
    };
    await _db.transaction((txn) async {
      await txn.insert('enfant', {
        'id': id,
        ...payload,
        'sync_status': SyncStatus.pending.name,
        'created_at': now,
        'updated_at': now,
      });
      await Outbox.enqueue(txn, table: 'enfant', operation: 'create', rowId: id, payload: payload);
    });
    return (await child(id))!;
  }

  /// Corrects a child's identity. Sent as an update with the version this
  /// phone last saw: if the server changed meanwhile, it becomes a conflict.
  Future<Child> updateChild(String id, {String? name, String? sex, DateTime? birthDate}) async {
    final current = (await child(id))!;
    final changes = <String, Object?>{
      'nom': ?name?.trim(),
      'sexe': ?sex,
      if (birthDate != null) 'date_naissance': isoDate(birthDate),
    };
    if (changes.isEmpty) return current;
    await _db.transaction((txn) async {
      await txn.update(
        'enfant',
        {...changes, 'sync_status': SyncStatus.pending.name, 'updated_at': _now()},
        where: 'id = ?',
        whereArgs: [id],
      );
      await Outbox.enqueue(
        txn,
        table: 'enfant',
        operation: 'update',
        rowId: id,
        version: current.version,
        payload: changes,
      );
    });
    return (await child(id))!;
  }

  // ------------------------------------------------------------ measurements

  Future<List<Measurement>> measurements(String childId) async => (await _db.query(
    'mesure',
    where: 'enfant_id = ?',
    whereArgs: [childId],
    orderBy: 'date_mesure DESC, created_at DESC',
  )).map(Measurement.fromRow).toList();

  Future<Measurement?> measurement(String id) async {
    final rows = await _db.query('mesure', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Measurement.fromRow(rows.first);
  }

  Future<Measurement> saveMeasurement({
    required Child child,
    required ScreeningInput input,
    required ScreeningResult result,
    required String agentId,
  }) async {
    final id = newUuid();
    final now = _now();
    String? z(double? v) => v?.toStringAsFixed(2);
    final payload = <String, Object?>{
      'enfant_id': child.id,
      'asc_id': agentId,
      'date_mesure': isoDate(input.measureDate),
      'poids_kg': input.weightKg.toStringAsFixed(2),
      'taille_cm': input.lengthCm.toStringAsFixed(1),
      'position': input.position,
      'pb_mm': input.muacMm,
      'oedemes_bilateraux': input.oedema,
      'waz': z(result.zscores.waz),
      'haz': z(result.zscores.haz),
      'whz': z(result.zscores.whz),
      'flag_aberrant': result.needsCheck,
      'alerte': result.alerte,
      'motif_alerte': result.classification == null ? '' : ScreeningCalculator.motif(input, result),
      'signes_danger': input.dangerSigns,
      'complications_medicales': input.complications,
      'appetit': input.appetite,
      'difficultes_allaitement': input.breastfeedingDifficulties,
    };
    await _db.transaction((txn) async {
      await txn.insert('mesure', {
        'id': id,
        'enfant_id': child.id,
        'date_mesure': payload['date_mesure'],
        'poids_kg': input.weightKg,
        'taille_cm': input.lengthCm,
        'position': input.position,
        'pb_mm': input.muacMm,
        'oedemes_bilateraux': input.oedema,
        'signes_danger': jsonEncode(input.dangerSigns),
        'complications_medicales': input.complications ? 1 : 0,
        'appetit': input.appetite,
        'difficultes_allaitement': input.breastfeedingDifficulties ? 1 : 0,
        'age_jour': result.ageDays,
        'age_mois': result.ageMonths,
        'taille_corrigee_cm': result.correctedLengthCm,
        'waz': result.zscores.waz,
        'haz': result.zscores.haz,
        'whz': result.zscores.whz,
        'flag_aberrant': result.needsCheck ? 1 : 0,
        'classification': result.classification,
        'orientation_centre': result.centre,
        'urgence': result.urgence,
        'date_prochain_controle': result.nextCheck == null ? null : isoDate(result.nextCheck!),
        'config_version': result.configVersion,
        'alerte': result.alerte,
        'motif_alerte': payload['motif_alerte'],
        'sync_status': SyncStatus.pending.name,
        'created_at': now,
        'updated_at': now,
      });
      await Outbox.enqueue(txn, table: 'mesure', operation: 'create', rowId: id, payload: payload);
    });
    return (await measurement(id))!;
  }

  // ---------------------------------------------------------------- referrals

  Future<Referral> createReferral({
    required Child child,
    required Measurement measurement,
    required ScreeningResult result,
    required Centre centre,
    required String motif,
    required String agentId,
  }) async {
    final id = newUuid();
    final code = await codes.next();
    final now = _clock.now().toUtc();
    final payload = <String, Object?>{
      'code_unique': code,
      'origine': 'enfant',
      'enfant_id': child.id,
      'mesure_id': measurement.id,
      'asc_id': agentId,
      'csb_id': centre.id,
      'priorite': result.priorite,
      'motif': motif,
      'date_referencement': now.toIso8601String(),
    };
    await _db.transaction((txn) async {
      await txn.insert('referencement', {
        'id': id,
        'code_unique': code,
        'origine': 'enfant',
        'enfant_id': child.id,
        'mesure_id': measurement.id,
        'csb_id': centre.id,
        'priorite': result.priorite,
        'urgence': result.urgence,
        'motif': motif,
        'date_referencement': now.toIso8601String(),
        'status': 'envoye',
        'sync_status': SyncStatus.pending.name,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await Outbox.enqueue(txn, table: 'referencement', operation: 'create', rowId: id, payload: payload);
    });
    return (await referral(id))!;
  }

  Future<Referral?> referral(String id) async {
    final rows = await _db.query('referencement', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Referral.fromRow(rows.first);
  }

  Future<List<Referral>> referrals({String? childId}) async => (await _db.query(
    'referencement',
    where: childId == null ? null : 'enfant_id = ?',
    whereArgs: childId == null ? null : [childId],
    orderBy: 'date_referencement DESC',
  )).map(Referral.fromRow).toList();

  // ------------------------------------------------------------------ centres

  Future<List<Centre>> centres({String? type}) async => (await _db.query(
    'centre',
    where: type == null ? null : 'type_centre = ?',
    whereArgs: type == null ? null : [type],
    orderBy: 'name',
  )).map(Centre.fromRow).toList();

  Future<Centre?> centre(int? id) async {
    if (id == null) return null;
    final rows = await _db.query('centre', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Centre.fromRow(rows.first);
  }

  Future<void> replaceCentres(List<Map<String, Object?>> rows) => _db.transaction((txn) async {
    await txn.delete('centre');
    for (final r in rows) {
      await txn.insert('centre', {
        'id': r['id'],
        'name': r['name'],
        'type_centre': r['type_centre'] ?? 'csb',
        'region_id': r['region_id'],
        'tel': r['tel'],
      });
    }
  });

  // --------------------------------------------------------------- follow-ups

  /// Referrals still "Référé" after the configured delay (spec §7: "non
  /// arrivés après 48 h", the delay comes from the configuration).
  Future<List<Referral>> notArrived({required int? delayHours}) async {
    if (delayHours == null) return const [];
    final limit = _clock.now().toUtc().subtract(Duration(hours: delayHours));
    return (await referrals()).where((r) => r.status == 'envoye' && r.referredAt.isBefore(limit)).toList();
  }

  /// Children whose last measurement has a next check that is due.
  Future<List<(Child, Measurement)>> childrenDue() async {
    final today = dateOnly(_clock.now());
    final rows = await _db.rawQuery('''
      SELECT m.* FROM mesure m
      WHERE m.date_mesure = (SELECT max(date_mesure) FROM mesure WHERE enfant_id = m.enfant_id)
        AND m.date_prochain_controle IS NOT NULL AND m.date_prochain_controle != ''
    ''');
    final out = <(Child, Measurement)>[];
    final seen = <String>{};
    for (final row in rows) {
      final m = Measurement.fromRow(row);
      if (!seen.add(m.childId)) continue;
      if (m.nextCheck == null || m.nextCheck!.isAfter(today)) continue;
      final c = await child(m.childId);
      if (c != null && c.careStatus != 'decede') out.add((c, m));
    }
    return out;
  }

  /// Appointments still planned after their date (from the server).
  Future<List<Appointment>> missedAppointments() async {
    final today = isoDate(_clock.now());
    final rows = await _db.query(
      'rendez_vous',
      where: "statut = 'prevu' AND date_prevue < ?",
      whereArgs: [today],
      orderBy: 'date_prevue',
    );
    return rows
        .map(
          (r) => Appointment(
            id: r['id']! as String,
            childId: r['enfant_id'] as String?,
            date: parseIsoDate((r['date_prevue']! as String).substring(0, 10)),
            status: r['statut'] as String?,
            reason: r['motif'] as String?,
          ),
        )
        .toList();
  }

  Future<int> pendingCount() => Outbox.count(_db);

  Future<int> openConflicts() async =>
      (await _db.rawQuery("SELECT count(*) AS n FROM conflit WHERE statut = 'a_verifier'")).first['n']!
          as int;
}
