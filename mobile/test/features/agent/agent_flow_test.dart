import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/features/agent/presentation/agent_scope.dart';

import '../../helpers/fake_server.dart';
import '../../helpers/test_env.dart';

void main() {
  testWidgets('scenario 5 in the agent UI: offline referral, then transmitted', (tester) async {
    final server = FakeServer();
    final network = FakeNetworkStatus();
    final env = await TestEnv.create(httpClient: server.client, network: network);
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Rasoa', pin: '1234', mode: ProfileMode.agent);
    });
    await settle(tester);

    // First login (online).
    expect(find.text('Connexion agent de santé'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('agent-login-id')), 'ac.rasoa');
    await tester.enterText(find.byKey(const ValueKey('agent-login-pin')), '1234');
    await tapKey(tester, 'agent-login-submit');
    expect(find.text('Dépister un enfant'), findsOneWidget);

    // Offline from now on.
    network.kind = NetworkKind.none;
    final agent = AgentScope.read(tester.element(find.text('Dépister un enfant')));
    await tester.runAsync(
      () => agent.repo.createChild(
        name: 'Soa',
        sex: 'F',
        birthDate: DateTime(2025, 5, 4),
        regionId: 1,
        agentId: 'agent-1',
      ),
    );

    await tapKey(tester, 'agent-screen');
    expect(find.text('Soa'), findsOneWidget);
    await tester.tap(find.text('Soa'));
    await settle(tester);
    await tapKey(tester, 'new-measure');
    await tester.enterText(find.byKey(const ValueKey('field-weight')), '8,6');
    await tester.enterText(find.byKey(const ValueKey('field-length')), '77,5');
    await tester.enterText(find.byKey(const ValueKey('field-muac')), '112');
    await tapKey(tester, 'measure-submit');

    expect(find.text('MAS – malnutrition aiguë sévère'), findsOneWidget);
    expect(find.text('Orienter vers : CRENAS'), findsOneWidget);
    expect(find.text('Urgence orange'), findsOneWidget);
    expect(find.textContaining('tables OMS absentes'), findsOneWidget);

    await tapKey(tester, 'create-referral');
    await tester.tap(find.byKey(const ValueKey('centre-3')));
    await settle(tester);
    expect(find.byKey(const ValueKey('referral-code')), findsOneWidget);
    expect(find.text('Non transmise — à montrer au centre'), findsOneWidget);

    // Back online: the sync transmits it.
    network.kind = NetworkKind.wifi;
    await tester.runAsync(() => agent.syncNow(manual: true));
    await settle(tester);
    expect(find.text('Non transmise — à montrer au centre'), findsNothing);
    expect(find.text('Transmise au serveur'), findsOneWidget);
    expect(server.tables['referencement']!.length, 1);

    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });

  testWidgets('personal mode: the agent tile needs a separate agent profile', (tester) async {
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Voahangy', pin: '1234', mode: ProfileMode.personal);
    });
    await settle(tester);
    await tapKey(tester, 'tile-agent');
    expect(find.byKey(const ValueKey('agent-access-create')), findsOneWidget);
    await tester.runAsync(session.lock);
    await settle(tester);
    env.dir.deleteSync(recursive: true);
  });
}
