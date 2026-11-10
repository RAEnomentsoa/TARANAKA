import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'app/session_controller.dart';
import 'core/config/config_repository.dart';
import 'core/db/db_opener.dart';
import 'core/security/profile_registry.dart';
import 'core/security/secret_store.dart';
import 'core/sync/network_status.dart';
import 'core/util/clock.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local only (no network): Firebase is reached when the recovery by e-mail
  // is used. A failure must never keep the app from opening.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on Exception catch (e) {
    debugPrint('Firebase not available: $e');
  }
  final secrets = KeystoreSecretStore();
  final services = AppServices(
    secrets: secrets,
    registry: ProfileRegistry(secrets),
    config: ConfigRepository(directory: getApplicationSupportDirectory),
    dbOpener: const SqlCipherOpener(),
    dataDirectory: getApplicationSupportDirectory,
    device: DeviceIdentity(secrets),
    clock: const SystemClock(),
    network: DeviceNetworkStatus(),
  );
  final session = SessionController(services);
  await session.init();
  runApp(TaranakaApp(services: services, session: session));
}
