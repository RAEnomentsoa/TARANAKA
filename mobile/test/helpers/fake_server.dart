import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A tiny in-memory imitation of the TARANAKA sync API, enough to test the
/// phone's outbox logic: idempotency keys, versions, clinical conflicts,
/// soft deletions, cursors, gzip bodies and token refresh.
class FakeServer {
  final Map<String, Map<String, Map<String, Object?>>> tables = {
    for (final name in const [
      'cycle',
      'cycle_jour',
      'alimentation_femme',
      'grossesse',
      'danger_grossesse',
      'contact_soin',
      'suivi_grossesse',
      'mouvement_bebe',
      'mouvement_evenement',
      'enfant',
      'mesure',
      'journal_alimentaire',
      'vaccin_fait',
      'tetee',
      'referencement',
      'rendez_vous',
    ])
      name: <String, Map<String, Object?>>{},
  };

  // ---- beneficiary accounts (D16)

  /// Regions of `/api/auth/access-request/options/`.
  List<Map<String, Object?>> regions = [
    {'id': 1, 'nom': 'Analamanga'},
    {'id': 2, 'nom': 'Vakinankaratra'},
  ];

  /// Beneficiaries by id: what `/api/beneficiaries/` lists.
  final Map<String, Map<String, Object?>> beneficiaries = {};
  final List<Map<String, Object?>> registrations = [];
  bool cycleShared = false;
  final List<bool> cycleSharingCalls = [];
  final List<Map<String, Object?>> erasures = [];
  final List<Map<String, Object?>> pinChanges = [];
  String beneficiaryPin = '1234';

  /// Adds a woman of the zone (and her code).
  Map<String, Object?> addBeneficiary({
    required String id,
    required String prenom,
    String nom = '',
    String code = 'K7QM4Z',
    String? identifiant,
  }) => beneficiaries[id] = {
    'id': id,
    'identifiant': identifiant ?? '${prenom.toLowerCase()}.4821',
    'prenom': prenom,
    'nom': nom,
    'phone': null,
    'region_id': 1,
    'code_beneficiaire': code,
    'partage_cycle': false,
  };

  Map<String, Object?> _file(String id) {
    final who = beneficiaries[id]!;
    List<Map<String, Object?>> rows(String table, bool Function(Map<String, Object?>) keep) =>
        tables[table]!.values.where((r) => r['deleted_at'] == null && keep(r)).toList();
    final pregnancies = rows('grossesse', (r) => r['user_id'] == id);
    final pIds = {for (final p in pregnancies) p['id']};
    final children = rows('enfant', (r) => r['mere_id'] == id);
    final cIds = {for (final c in children) c['id']};
    return {
      'beneficiaire': who,
      'grossesses': pregnancies,
      'signes_danger': rows('danger_grossesse', (r) => pIds.contains(r['grossesse_id'])),
      'contacts_soin': rows('contact_soin', (r) => pIds.contains(r['grossesse_id'])),
      'suivis_grossesse': rows('suivi_grossesse', (r) => pIds.contains(r['grossesse_id'])),
      'mouvements_bebe': <Object?>[],
      'mouvements_evenements': <Object?>[],
      'alimentations': <Object?>[],
      'cycles': <Object?>[],
      'cycle_jours': <Object?>[],
      'enfants': children,
      'mesures': rows('mesure', (r) => cIds.contains(r['enfant_id'])),
      'journaux_alimentaires': rows('journal_alimentaire', (r) => cIds.contains(r['enfant_id'])),
      'vaccins': rows('vaccin_fait', (r) => cIds.contains(r['enfant_id'])),
      'tetees': <Object?>[],
      'rendez_vous': <Object?>[],
      'referencements': rows(
        'referencement',
        (r) => pIds.contains(r['grossesse_id']) || cIds.contains(r['enfant_id']),
      ),
    };
  }

  Map<String, Object?> _beneficiaryUser(Map<String, Object?> b) => {
    'id': b['id'],
    'identifiant': b['identifiant'],
    'nom': b['nom'],
    'prenom': b['prenom'],
    'profile': {'code': 'beneficiaire', 'libelle': 'Bénéficiaire'},
    'region_id': b['region_id'],
    'csb_id': null,
    'code_beneficiaire': b['code_beneficiaire'],
    'partage_cycle': cycleShared,
  };
  final Map<String, Map<String, Object?>> answers = {};
  final List<Map<String, Object?>> pushes = [];
  final Set<String> usedCodes = {};
  bool offline = false;

  /// Applies the next push, then loses the answer (network cut).
  bool loseNextPushAnswer = false;
  bool expireAccessOnce = false;
  int refreshes = 0;
  int clock = 0;
  bool lastPushWasGzip = false;
  String? lastDeviceId;
  Map<String, Object?>? configUpdate;

  String _ts() => DateTime.utc(2026, 11, 4).add(Duration(seconds: clock++)).toIso8601String();

  late final http.Client client = MockClient((request) async {
    if (offline) throw const SocketException('offline');
    lastDeviceId = request.headers['X-Device-Id'];
    final path = request.url.path;
    if (path == '/api/auth/login/') {
      final body = jsonDecode(request.body) as Map;
      // '123456': an account code longer than the 4-digit local PIN.
      if (body['pin'] != '1234' && body['pin'] != '123456') {
        return http.Response(jsonEncode({'code': 'identifiants_incorrects'}), 401);
      }
      return _json({
        'access': 'A1',
        'refresh': 'R1',
        'totp_a_configurer': false,
        'utilisateur': {
          'id': 'agent-1',
          'nom': 'Rasoanirina',
          'prenom': 'Rasoa',
          'profile': {'code': body['identifiant'] == 'inf.crenas' ? 'agent_csb' : 'asc', 'libelle': ''},
          'region_id': 1,
          'csb_id': null,
        },
      });
    }
    if (path == '/api/auth/access-request/options/') {
      return _json({'regions': regions, 'centres': <Object?>[]});
    }
    if (path == '/api/auth/register-beneficiary/') {
      final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
      registrations.add(body);
      if (body['consentement'] != true || body['region_id'] == null) {
        return http.Response(
          jsonEncode({
            'consentement': ['obligatoire'],
          }),
          400,
        );
      }
      beneficiaryPin = body['pin']! as String;
      cycleShared = body['partage_cycle'] == true;
      final b = addBeneficiary(id: 'mere-${registrations.length}', prenom: body['prenom']! as String);
      return http.Response(
        jsonEncode({'access': 'A1', 'refresh': 'R1', 'utilisateur': _beneficiaryUser(b)}),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (path == '/api/auth/me/' && request.method == 'PATCH') {
      final share = (jsonDecode(request.body) as Map)['partage_cycle'] == true;
      cycleSharingCalls.add(share);
      cycleShared = share;
      var deleted = 0;
      if (!share) {
        for (final t in ['cycle', 'cycle_jour']) {
          deleted += tables[t]!.length;
          tables[t]!.clear();
        }
      }
      return _json({
        'utilisateur': _beneficiaryUser(beneficiaries.values.first),
        'lignes_supprimees': deleted,
      });
    }
    if (path == '/api/auth/changer-pin/') {
      final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
      pinChanges.add(body);
      if (body['ancien_pin'] != beneficiaryPin) {
        return http.Response(jsonEncode({'code': 'ancien_pin_incorrect'}), 400);
      }
      beneficiaryPin = body['nouveau_pin']! as String;
      return _json({'detail': 'PIN modifié.', 'access': 'A3', 'refresh': 'R3'});
    }
    if (path == '/api/auth/my-data/erase/') {
      final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
      if (body['pin'] != beneficiaryPin) return http.Response(jsonEncode({'code': 'pin_incorrect'}), 400);
      erasures.add(body);
      return _json({'detail': 'Les données ont été effacées.', 'resume': <String, Object?>{}});
    }
    if (path == '/api/beneficiaries/lookup/') {
      final code = ((jsonDecode(request.body) as Map)['code'] as String).replaceAll('-', '').toUpperCase();
      final b = beneficiaries.values.where((b) => b['code_beneficiaire'] == code).firstOrNull;
      if (b == null) return http.Response(jsonEncode({'detail': 'Introuvable.'}), 404);
      return _json(_file(b['id']! as String));
    }
    if (path.startsWith('/api/beneficiaries/') && path.length > '/api/beneficiaries/'.length) {
      final id = path.substring('/api/beneficiaries/'.length).replaceAll('/', '');
      if (!beneficiaries.containsKey(id)) return http.Response('{}', 404);
      return _json(_file(id));
    }
    if (path == '/api/beneficiaries/') {
      final q = (request.url.queryParameters['q'] ?? '').toLowerCase();
      final list = [
        for (final b in beneficiaries.values)
          if (q.isEmpty || '${b['prenom']} ${b['nom']} ${b['code_beneficiaire']}'.toLowerCase().contains(q))
            {
              ...b,
              'suivie': false,
              'grossesse_en_cours': false,
              'nb_enfants': tables['enfant']!.values.where((c) => c['mere_id'] == b['id']).length,
            },
      ];
      return _json({'count': list.length, 'next': null, 'results': list});
    }
    if (path == '/api/profiles/' && request.method == 'POST') {
      final body = (jsonDecode(request.body) as Map).cast<String, Object?>();
      final id = 'mere-asc-${beneficiaries.length + 1}';
      final b = addBeneficiary(
        id: id,
        prenom: body['prenom']! as String,
        nom: (body['nom'] as String?) ?? '',
        code: 'ASC${beneficiaries.length + 1}',
      );
      return http.Response(
        jsonEncode({
          ...b,
          'consentement': true,
          'profile': {'code': 'beneficiaire', 'libelle': 'Bénéficiaire'},
        }),
        201,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (path == '/api/auth/refresh/') {
      refreshes++;
      return _json({'access': 'A2', 'refresh': 'R2'});
    }
    if (expireAccessOnce && request.headers['Authorization'] == 'Bearer A1') {
      expireAccessOnce = false;
      return http.Response('{"code":"token_not_valid"}', 401);
    }
    if (path == '/api/sync/push/') {
      lastPushWasGzip = request.headers['Content-Encoding'] == 'gzip';
      final raw = lastPushWasGzip ? utf8.decode(gzip.decode(request.bodyBytes)) : request.body;
      final ops = ((jsonDecode(raw) as Map)['operations'] as List).cast<Map<String, Object?>>();
      pushes.add({'operations': ops});
      final results = ops.map(_apply).toList();
      if (loseNextPushAnswer) {
        loseNextPushAnswer = false;
        throw const SocketException('connection reset');
      }
      return _json({'horodatage_serveur': _ts(), 'resultats': results});
    }
    if (path == '/api/sync/pull/') {
      final q = request.url.queryParameters;
      final names = q['tables']!.split(',');
      final since = q['depuis'];
      final limit = int.parse(q['limite'] ?? '500');
      final out = <String, Object?>{};
      for (final name in names) {
        final rows =
            tables[name]!.values
                .where((r) => since == null || (r['updated_at']! as String).compareTo(since) > 0)
                .toList()
              ..sort((a, b) => (a['updated_at']! as String).compareTo(b['updated_at']! as String));
        final page = rows.take(limit).toList();
        final more = rows.length > limit;
        out[name] = {
          'lignes': page,
          'suite': more,
          'prochain_depuis': more ? page.last['updated_at'] : _ts(),
          'apres_id': more ? page.last['id'] : null,
        };
      }
      final update = q['config_version'] != null ? configUpdate : null;
      return _json({
        'horodatage_serveur': _ts(),
        'tables': out,
        'conflits': [],
        'config_clinique': {'version': 1, 'mise_a_jour': update},
      });
    }
    if (path == '/api/facilities/') {
      return _json({
        'count': 2,
        'next': null,
        'results': [
          {'id': 3, 'name': 'CRENAS Ambohitsoa', 'type_centre': 'crenas', 'region_id': 1, 'tel': '020'},
          {'id': 4, 'name': 'CRENI Tanàna', 'type_centre': 'creni', 'region_id': 1, 'tel': '021'},
        ],
      });
    }
    return http.Response('not found', 404);
  });

  Map<String, Object?> _apply(Map<String, Object?> op) {
    final key = op['cle_idempotence']! as String;
    if (answers.containsKey(key)) return {...answers[key]!, 'rejoue': true};
    final table = tables[op['table']]!;
    final id = op['id']! as String;
    if ((op['table'] == 'cycle' || op['table'] == 'cycle_jour') && !cycleShared) {
      return {
        'cle_idempotence': key,
        'table': op['table'],
        'operation': op['operation'],
        'id': id,
        'statut': 'refuse',
        'ligne': null,
        'conflit_id': null,
        'erreurs': {'detail': 'partage_cycle'},
        'rejoue': false,
      };
    }
    final base = {
      'cle_idempotence': key,
      'table': op['table'],
      'operation': op['operation'],
      'id': id,
      'conflit_id': null,
      'erreurs': null,
      'rejoue': false,
    };
    Map<String, Object?> answer;
    switch (op['operation']) {
      case 'create':
        if (table.containsKey(id)) {
          answer = {...base, 'statut': 'deja_applique', 'ligne': table[id]};
          break;
        }
        final data = (op['donnees']! as Map).cast<String, Object?>();
        if (op['table'] == 'mesure' && !tables['enfant']!.containsKey(data['enfant_id'])) {
          return {
            ...base,
            'statut': 'erreur',
            'ligne': null,
            'erreurs': {
              'enfant_id': ['inconnu'],
            },
          };
        }
        if (op['table'] == 'referencement' && !usedCodes.add(data['code_unique']! as String)) {
          return {
            ...base,
            'statut': 'erreur',
            'ligne': null,
            'erreurs': {
              'code_unique': ['déjà utilisé'],
            },
          };
        }
        final row = <String, Object?>{
          ...data,
          'id': id,
          'version': 1,
          'updated_at': _ts(),
          'deleted_at': null,
          if (op['table'] == 'mesure') ...{
            'classification': 'mas',
            'orientation_centre': 'crenas',
            'urgence': 'orange',
          },
          if (op['table'] == 'referencement') ...{'status': 'envoye', 'urgence': 'orange'},
          if (op['table'] == 'enfant') 'statut_prise_en_charge': 'aucun',
        };
        table[id] = row;
        answer = {...base, 'statut': 'applique', 'ligne': row};
      case 'update':
        final row = table[id];
        if (row == null) return {...base, 'statut': 'introuvable', 'ligne': null};
        if (row['version'] != op['version']) {
          answer = {...base, 'statut': 'conflit', 'ligne': row, 'conflit_id': 'conflict-$id'};
          break;
        }
        final updated = {
          ...row,
          ...(op['donnees']! as Map).cast<String, Object?>(),
          'version': (row['version']! as int) + 1,
          'updated_at': _ts(),
        };
        table[id] = updated;
        answer = {...base, 'statut': 'applique', 'ligne': updated};
      default:
        final row = table[id];
        if (row == null) return {...base, 'statut': 'introuvable', 'ligne': null};
        table[id] = {...row, 'deleted_at': _ts(), 'updated_at': _ts()};
        answer = {...base, 'statut': 'applique', 'ligne': null};
    }
    answers[key] = answer;
    return answer;
  }

  /// A change made elsewhere (web dashboard, other phone).
  void serverEdit(String table, String id, Map<String, Object?> changes) {
    final row = tables[table]![id]!;
    tables[table]![id] = {...row, ...changes, 'version': (row['version']! as int) + 1, 'updated_at': _ts()};
  }

  static http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}
