import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taranaka/app/app.dart';
import 'package:taranaka/app/app_services.dart';
import 'package:taranaka/app/session_controller.dart';
import 'package:taranaka/core/config/config_repository.dart';
import 'package:taranaka/core/db/db_opener.dart';
import 'package:taranaka/core/growth/who_lms.dart';
import 'package:taranaka/core/security/profile_registry.dart';
import 'package:http/http.dart' as http;
import 'package:taranaka/core/security/secret_store.dart';
import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/core/util/clock.dart';

/// SQLCipher on the host (system libsqlcipher, see pubspec `hooks`), opened
/// the same way sqflite_sqlcipher does on the phone: `PRAGMA key` first.
class FfiCipherOpener implements DbOpener {
  FfiCipherOpener() {
    sqfliteFfiInit();
  }

  @override
  Future<Database> open(
    String path, {
    required String passphrase,
    required int version,
    required OnDatabaseCreateFn onCreate,
    required OnDatabaseVersionChangeFn onUpgrade,
  }) => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      singleInstance: false,
      onConfigure: (db) async {
        await db.execute("PRAGMA key = '$passphrase'");
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    ),
  );

  @override
  Future<void> delete(String path) => databaseFactoryFfi.deleteDatabase(path);
}

class TestEnv {
  TestEnv._(this.dir, this.services, this.secrets, this.clock);

  final Directory dir;
  final AppServices services;
  final MemorySecretStore secrets;
  final FixedClock clock;

  static Future<TestEnv> create({
    MemorySecretStore? secrets,
    Directory? dir,
    String? apiBaseUrl,
    http.Client? httpClient,
    NetworkStatus? network,
  }) async {
    final directory = dir ?? Directory.systemTemp.createTempSync('taranaka_test');
    final store = secrets ?? MemorySecretStore();
    final clock = FixedClock(DateTime(2026, 11, 4, 9));
    final services = AppServices(
      secrets: store,
      registry: ProfileRegistry(store, clock: clock),
      config: ConfigRepository(directory: () async => directory),
      dbOpener: FfiCipherOpener(),
      dataDirectory: () async => directory,
      device: DeviceIdentity(store),
      clock: clock,
      network: network ?? FakeNetworkStatus(),
      whoTables: WhoTables.empty,
      httpClient: httpClient,
      defaultApiBaseUrl: apiBaseUrl ?? 'http://localhost:8000',
    );
    return TestEnv._(directory, services, store, clock);
  }

  Future<SessionController> session() async {
    final session = SessionController(services);
    await session.init();
    return session;
  }
}

/// Pumps the whole app; real async work (SQLite, files) runs outside the fake clock.
Future<SessionController> pumpApp(WidgetTester tester, TestEnv env) async {
  final session = await tester.runAsync(env.session);
  await tester.pumpWidget(TaranakaApp(services: env.services, session: session!));
  await settle(tester);
  return session;
}

/// Lets real I/O (SQLCipher runs on a background isolate) finish, then lets
/// frames settle. Stops early once nothing is scheduled any more.
Future<void> settle(WidgetTester tester, {int rounds = 80}) async {
  var quiet = 0;
  for (var i = 0; i < rounds && quiet < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await tester.pump(const Duration(milliseconds: 50));
    quiet = tester.binding.hasScheduledFrame ? 0 : quiet + 1;
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    // Lazily built list item: scroll the page until it exists.
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump(); // lay out at the new scroll position before tapping
  await tester.tap(finder);
  await settle(tester);
}

Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('pin-$d')).last);
    await tester.pump();
  }
  await settle(tester);
}
