import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/db/app_database.dart';
import '../../../core/sync/outbox.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_tables.dart';
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

  /// A child is always attached to its mother, a beneficiary (D16: no child
  /// without a mother any more), and to her pregnancy when known.
  Future<Child> createChild({
    required String name,
    required String sex,
    required DateTime birthDate,
    required int? regionId,
    required String agentId,
    required String motherId,
    String? pregnancyId,
  }) async {
    if (motherId.isEmpty) throw ArgumentError.value(motherId, 'motherId', 'a child needs its mother');
    final id = newUuid();
    final now = _now();
    final payload = {
      'nom': name.trim(),
      'sexe': sex,
      'date_naissance': isoDate(birthDate),
      'region_id': regionId,
      'asc_id': agentId,
      'mere_id': motherId,
      'grossesse_id': ?pregnancyId,
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

  Future<List<Child>> childrenOf(String motherId) async => (await _db.query(
    'enfant',
    where: 'mere_id = ?',
    whereArgs: [motherId],
    orderBy: 'date_naissance DESC',
  )).map(Child.fromRow).toList();

  // ----------------------------------------------------------- beneficiaries

  /// Women already seen on this phone (list of the zone, or files opened).
  Future<List<Beneficiary>> beneficiaries({String search = '', bool followedOnly = false}) async {
    final q = search.trim().toLowerCase().replaceAll('-', '');
    final where = [
      if (followedOnly) 'suivie = 1',
      if (q.isNotEmpty)
        "(lower(prenom || ' ' || nom) LIKE ? OR replace(lower(coalesce(code_beneficiaire, '')), '-', '') LIKE ? "
            "OR coalesce(phone, '') LIKE ? OR lower(coalesce(identifiant, '')) LIKE ?)",
    ];
    final rows = await _db.query(
      'beneficiaire',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%', '%$q%', '%$q%'],
      orderBy: 'suivie DESC, prenom COLLATE NOCASE',
    );
    return rows.map(Beneficiary.fromRow).toList();
  }

  Future<Beneficiary?> beneficiary(String id) async {
    final rows = await _db.query('beneficiaire', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Beneficiary.fromRow(rows.first);
  }

  /// Lines of `/api/beneficiaries/` (or of a file): kept to work offline.
  Future<void> saveBeneficiaries(List<Map<String, Object?>> lines) => _db.transaction((txn) async {
    for (final l in lines) {
      await _saveBeneficiary(txn, l);
    }
  });

  Future<void> _saveBeneficiary(DatabaseExecutor txn, Map<String, Object?> l, {bool? followed}) async {
    final values = <String, Object?>{
      'id': l['id'],
      'prenom': l['prenom'] ?? '',
      'nom': l['nom'] ?? '',
      'phone': l['phone'],
      'region_id': l['region_id'],
      'code_beneficiaire': l['code_beneficiaire'],
      if (l.containsKey('identifiant')) 'identifiant': l['identifiant'],
      if (l.containsKey('grossesse_en_cours')) 'grossesse_en_cours': l['grossesse_en_cours'] == true ? 1 : 0,
      if (l.containsKey('nb_enfants')) 'nb_enfants': l['nb_enfants'],
      if (l.containsKey('partage_cycle')) 'partage_cycle': l['partage_cycle'] == true ? 1 : 0,
      if (followed != null || l.containsKey('suivie')) 'suivie': (followed ?? l['suivie'] == true) ? 1 : 0,
      'updated_at': _now(),
    };
    final n = await txn.update('beneficiaire', values, where: 'id = ?', whereArgs: [l['id']]);
    if (n == 0) await txn.insert('beneficiaire', values);
  }

  /// Her whole file (`/api/beneficiaries/{id}/` or `lookup/`): she is now
  /// followed; her clinical rows go to the local tables (as with the pull),
  /// and the file itself is kept to be read offline. Rows this phone still
  /// has to send are not overwritten.
  Future<Beneficiary> saveFile(Map<String, Object?> file) async {
    final who = (file['beneficiaire']! as Map).cast<String, Object?>();
    final sections = <String, SyncTable>{
      'grossesses': SyncTables.pregnancy,
      'signes_danger': SyncTables.danger,
      'contacts_soin': SyncTables.careContact,
      'suivis_grossesse': SyncTables.pregnancyCheck,
      'enfants': SyncTables.child,
      'mesures': SyncTables.measurement,
      'journaux_alimentaires': SyncTables.feedingLog,
      'vaccins': SyncTables.vaccine,
      'referencements': SyncTables.referral,
      'rendez_vous': SyncTables.appointment,
    };
    await _db.transaction((txn) async {
      await _saveBeneficiary(txn, who, followed: true);
      final enfants = (file['enfants'] as List?) ?? const [];
      final grossesses = (file['grossesses'] as List?) ?? const [];
      await txn.update(
        'beneficiaire',
        {
          'dossier': jsonEncode(file),
          'dossier_at': _now(),
          'nb_enfants': enfants.length,
          'grossesse_en_cours':
              grossesses.whereType<Map<Object?, Object?>>().any(
                (g) => g['terminee'] != true && g['date_accouchement'] == null,
              )
              ? 1
              : 0,
        },
        where: 'id = ?',
        whereArgs: [who['id']],
      );
      for (final MapEntry(key: section, value: table) in sections.entries) {
        for (final raw
            in (file[section] as List?)?.whereType<Map<Object?, Object?>>() ??
                const <Map<Object?, Object?>>[]) {
          final line = raw.cast<String, Object?>();
          final id = line['id'] as String?;
          if (id == null || line['deleted_at'] != null) continue;
          if (await Outbox.hasPendingFor(txn, table.name, id)) continue;
          try {
            await SyncEngine.upsert(txn, table.adapter, {
              ...table.toLocal(line),
              'sync_status': SyncStatus.synced.name,
            });
          } on DatabaseException {
            // A row whose parent is not on this phone: skipped.
          }
        }
      }
    });
    return (await beneficiary(who['id']! as String))!;
  }

  // ---------------------------------------------------------- her pregnancy

  Future<List<AgentPregnancy>> pregnanciesOf(String userId) async => (await _db.query(
    'grossesse',
    where: 'user_id = ?',
    whereArgs: [userId],
    orderBy: 'created_at DESC',
  )).map(AgentPregnancy.fromRow).toList();

  Future<List<(String, DateTime)>> dangersOf(String pregnancyId) async => [
    for (final r in await _db.query(
      'danger_grossesse',
      where: 'grossesse_id = ?',
      whereArgs: [pregnancyId],
      orderBy: 'date_signalement DESC',
    ))
      (r['code']! as String, DateTime.parse(r['date_signalement']! as String)),
  ];

  Future<int> antenatalContactsOf(String pregnancyId) async =>
      (await _db.rawQuery("SELECT count(*) AS n FROM contact_soin WHERE grossesse_id = ? AND type = 'cpn'", [
            pregnancyId,
          ])).first['n']!
          as int;

  /// Doses received, by code, with their date.
  Future<Map<String, DateTime>> vaccinesOf(String childId) async => {
    for (final r in await _db.query('vaccin_fait', where: 'enfant_id = ?', whereArgs: [childId]))
      r['code']! as String: parseIsoDate(r['date_faite']! as String),
  };

  /// A pregnancy recorded by the agent for a woman (e.g. without a phone).
  Future<AgentPregnancy> createPregnancy({required String userId, DateTime? lmp, DateTime? dueDate}) async {
    if (lmp == null && dueDate == null) throw ArgumentError('lmp or dueDate');
    final id = newUuid();
    final now = _now();
    final due = dueDate ?? (lmp == null ? null : addDays(lmp, 280));
    final payload = <String, Object?>{
      'user_id': userId,
      'ddr': lmp == null ? null : isoDate(lmp),
      'dpa': due == null ? null : isoDate(due),
      if (dueDate != null) 'dpa_saisie': isoDate(dueDate),
    };
    await _db.transaction((txn) async {
      await txn.insert('grossesse', {
        'id': id,
        ...payload,
        'sync_status': SyncStatus.pending.name,
        'created_at': now,
        'updated_at': now,
      });
      await Outbox.enqueue(txn, table: 'grossesse', operation: 'create', rowId: id, payload: payload);
    });
    return (await pregnanciesOf(userId)).firstWhere((p) => p.id == id);
  }

  /// Refers a pregnant woman (D16): each danger sign is recorded with its
  /// config `code` and `periode`, then one referral `origine: grossesse`.
  /// The signs are sent without `csb_id`, so the server creates no second
  /// referral of its own.
  Future<Referral> createPregnancyReferral({
    required AgentPregnancy pregnancy,
    required List<String> signs,
    required Centre centre,
    required String motif,
    required String agentId,
    String period = 'grossesse',
  }) async {
    final id = newUuid();
    final code = await codes.next();
    final now = _clock.now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      for (final sign in signs) {
        final dangerId = newUuid();
        final danger = <String, Object?>{
          'grossesse_id': pregnancy.id,
          'code': sign,
          'periode': period,
          'date_signalement': now,
        };
        await txn.insert('danger_grossesse', {
          'id': dangerId,
          ...danger,
          'sync_status': SyncStatus.pending.name,
          'created_at': now,
          'updated_at': now,
        });
        await Outbox.enqueue(
          txn,
          table: 'danger_grossesse',
          operation: 'create',
          rowId: dangerId,
          payload: danger,
        );
      }
      final payload = <String, Object?>{
        'code_unique': code,
        'origine': 'grossesse',
        'grossesse_id': pregnancy.id,
        'asc_id': agentId,
        'csb_id': centre.id,
        'priorite': 'urgente',
        'motif': motif,
        'date_referencement': now,
      };
      await txn.insert('referencement', {
        'id': id,
        'code_unique': code,
        'origine': 'grossesse',
        'grossesse_id': pregnancy.id,
        'csb_id': centre.id,
        'priorite': 'urgente',
        'urgence': 'rouge',
        'motif': motif,
        'date_referencement': now,
        'status': 'envoye',
        'sync_status': SyncStatus.pending.name,
        'created_at': now,
        'updated_at': now,
      });
      await Outbox.enqueue(txn, table: 'referencement', operation: 'create', rowId: id, payload: payload);
    });
    return (await referral(id))!;
  }

  Future<List<Referral>> referralsOfPregnancy(String pregnancyId) async => (await _db.query(
    'referencement',
    where: 'grossesse_id = ?',
    whereArgs: [pregnancyId],
    orderBy: 'date_referencement DESC',
  )).map(Referral.fromRow).toList();

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
