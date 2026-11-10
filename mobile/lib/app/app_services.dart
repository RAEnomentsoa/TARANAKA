import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/auth/auth_service.dart';
import '../core/config/config_repository.dart';
import '../core/db/db_opener.dart';
import '../core/growth/who_lms.dart';
import '../core/growth/who_tables_loader.dart';
import '../core/security/biometric_auth.dart';
import '../core/security/profile_registry.dart';
import '../core/security/secret_store.dart';
import '../core/sync/network_status.dart';
import '../core/util/clock.dart';
import '../core/util/ids.dart';

/// Install identifier, sent as `X-Device-Id` (audit log, spec §2) and used in
/// offline referral codes. Not personal: it identifies the app install.
class DeviceIdentity {
  DeviceIdentity(this._store);

  final SecretStore _store;
  static const _key = 'device_id_v1';
  String? _id;

  Future<String> id() async {
    if (_id != null) return _id!;
    var id = await _store.read(_key);
    if (id == null) {
      id = newUuid();
      await _store.write(_key, id);
    }
    return _id = id;
  }
}

/// Everything the app needs, created once in main() (or with fakes in tests).
class AppServices {
  AppServices({
    required this.secrets,
    required this.registry,
    required this.config,
    required this.dbOpener,
    required this.dataDirectory,
    required this.device,
    required this.clock,
    required this.network,
    this.httpClient,
    BiometricAuth? biometrics,
    AuthService? auth,
    WhoTables? whoTables,
    this.defaultApiBaseUrl = const String.fromEnvironment(
      'TARANAKA_API',
      defaultValue: 'https://api.taranaka.example',
    ),
  }) : biometrics = biometrics ?? LocalBiometricAuth(),
       auth = auth ?? FirebaseAuthService(),
       _whoTablesOverride = whoTables;

  final SecretStore secrets;
  final ProfileRegistry registry;
  final ConfigRepository config;
  final DbOpener dbOpener;

  /// Private app folder (profile databases, downloaded config).
  final Future<Directory> Function() dataDirectory;
  final DeviceIdentity device;
  final Clock clock;
  final NetworkStatus network;

  /// Fingerprint unlock (local_auth on the phone, a fake in tests).
  final BiometricAuth biometrics;

  /// Recovery by e-mail (Firebase Auth on the phone, a fake in tests).
  final AuthService auth;

  /// Null on the phone (default client); a fake one in tests.
  final http.Client? httpClient;
  final WhoTables? _whoTablesOverride;

  /// Official WHO tables bundled in assets/who/ (loaded once). Empty while the
  /// files are not in the app: no z-score is computed then.
  late final Future<WhoTables> whoTables = _whoTablesOverride != null
      ? Future.value(_whoTablesOverride)
      : WhoTablesLoader.load();

  /// Server used by agent mode; can be changed on the agent login screen.
  final String defaultApiBaseUrl;

  Future<String> profileDbPath(String profileId) async {
    final dir = Directory('${(await dataDirectory()).path}/profiles');
    await dir.create(recursive: true);
    return '${dir.path}/$profileId.db';
  }
}
