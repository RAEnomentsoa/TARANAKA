import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/alerts/alert_contact.dart';
import 'package:taranaka/core/growth/who_lms.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/features/child/data/child_repository.dart';

import '../helpers/test_env.dart';
import 'screenshot_helpers.dart';

void main() {
  testWidgets('part 3 screens', (tester) async {
    await loadRealFonts();
    await setPhone(tester);
    final env = await TestEnv.create();
    final session = await pumpApp(tester, env);
    late String id;
    await tester.runAsync(() async {
      await session.setLanguage('fr');
      await session.acceptConsent();
      await session.createProfile(displayName: 'Fara', pin: '1234', mode: ProfileMode.personal);
      await session.acceptConsent();
      final repo = ChildRepository(session.active!.db);
      final c = await repo.addChild(
        name: 'Kanto',
        sex: 'M',
        birthDate: DateTime(2026, 2, 1),
        birthWeightKg: 3.1,
      );
      id = c.id;
      for (final (d, w, l) in [
        (DateTime(2026, 4, 1), 5.1, 57.0),
        (DateTime(2026, 7, 1), 7.0, 64.5),
        (DateTime(2026, 11, 1), 8.1, 70.2),
      ]) {
        await repo.addGrowth(
          child: c,
          date: d,
          weightKg: w,
          lengthCm: l,
          position: 'couche',
          tables: WhoTables.empty,
          alerte: 'vert',
        );
      }
      await repo.markVaccine(id, 'bcg', DateTime(2026, 2, 1));
      await const AlertContact(
        centreName: 'CSB2 Ambohitsoa',
        centrePhone: '034 00 000 00',
      ).save(session.active!.db);
    });
    await settle(tester);
    await tapKey(tester, 'tile-child');
    await shot(tester, '20_my_children');
    await tapKey(tester, 'quick-feeding-$id');
    for (final f in ['vary', 'anana', 'lait_maternel']) {
      await tapKey(tester, 'food-$f');
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1000));
    await settle(tester);
    await shot(tester, '21_feeding');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    await tapKey(tester, 'my-child-$id');
    await shot(tester, '22_child_hub');
    await tapKey(tester, 'child-growth');
    await shot(tester, '23_growth');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    await tapKey(tester, 'child-vaccines');
    await shot(tester, '24_vaccines');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    await tapKey(tester, 'child-danger');
    await tester.tap(find.byKey(const ValueKey('danger-convulsions')));
    await tester.pump();
    await shot(tester, '25_red_alert');
    await tester.runAsync(session.lock);
    await settle(tester);
  }, skip: !screenshotsEnabled);
}
