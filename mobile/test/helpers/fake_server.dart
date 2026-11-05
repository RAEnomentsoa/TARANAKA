import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A tiny in-memory imitation of the TARANAKA sync API, enough to test the
/// phone's outbox logic: idempotency keys, versions, clinical conflicts,
/// soft deletions, cursors, gzip bodies and token refresh.
class FakeServer {
  final Map<String, Map<String, Map<String, Object?>>> tables = {
    'enfant': {},
    'mesure': {},
    'referencement': {},
    'rendez_vous': {},
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
      if (body['pin'] != '1234') {
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
