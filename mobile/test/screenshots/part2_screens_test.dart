import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/sync/network_status.dart';
import 'package:taranaka/features/agent/presentation/agent_scope.dart';

import '../helpers/fake_server.dart';
import '../helpers/test_env.dart';
import 'screenshot_helpers.dart';

void main() {
  testWidgets('part 2 screens', (tester) async {
    await loadRealFonts();
    await setPhone(tester);
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
    await shot(tester, '10_agent_login');
    await tester.enterText(find.byKey(const ValueKey('agent-login-id')), 'ac.rasoa');
    await tester.enterText(find.byKey(const ValueKey('agent-login-pin')), '1234');
    await tapKey(tester, 'agent-login-submit');
    network.kind = NetworkKind.none;
    final agent = AgentScope.read(tester.element(find.text('Dépister un enfant')));
    await tester.runAsync(
      () => agent.repo.createChild(
        name: 'Soa Rakotomalala',
        sex: 'F',
        birthDate: DateTime(2025, 5, 4),
        regionId: 1,
        agentId: 'agent-1',
        motherId: 'mere-1',
      ),
    );
    await tester.runAsync(agent.refreshCounts);
    await settle(tester);
    await shot(tester, '11_agent_home');
    await tapKey(tester, 'agent-screen');
    await tester.tap(find.text('Soa Rakotomalala'));
    await settle(tester);
    await tapKey(tester, 'new-measure');
    await tester.enterText(find.byKey(const ValueKey('field-weight')), '8,6');
    await tester.enterText(find.byKey(const ValueKey('field-length')), '77,5');
    await tester.enterText(find.byKey(const ValueKey('field-muac')), '112');
    await shot(tester, '12_measure_form');
    await tapKey(tester, 'measure-submit');
    await shot(tester, '13_result');
    await tapKey(tester, 'create-referral');
    await shot(tester, '14_centre_picker');
    await tester.tap(find.byKey(const ValueKey('centre-3')));
    await settle(tester);
    await shot(tester, '15_referral_sheet');
    await tester.runAsync(session.lock);
    await settle(tester);
  }, skip: !screenshotsEnabled);
}
