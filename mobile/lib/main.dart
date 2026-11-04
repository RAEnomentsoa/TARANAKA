import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'app/session_controller.dart';
import 'core/config/config_repository.dart';
import 'core/db/db_opener.dart';
import 'core/security/profile_registry.dart';
import 'core/security/secret_store.dart';
import 'core/util/clock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secrets = KeystoreSecretStore();
  final services = AppServices(
    secrets: secrets,
    registry: ProfileRegistry(secrets),
    config: ConfigRepository(directory: getApplicationSupportDirectory),
    dbOpener: const SqlCipherOpener(),
    dataDirectory: getApplicationSupportDirectory,
    device: DeviceIdentity(secrets),
    clock: const SystemClock(),
  );
  final session = SessionController(services);
  await session.init();
  runApp(TaranakaApp(services: services, session: session));
}
