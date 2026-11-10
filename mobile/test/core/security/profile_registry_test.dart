import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/auth/auth_service.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/security/profile_registry.dart';
import 'package:taranaka/core/security/secret_store.dart';
import 'package:taranaka/core/util/clock.dart';

import '../../helpers/fake_auth.dart';

void main() {
  late MemorySecretStore store;
  late FixedClock clock;
  late ProfileRegistry registry;

  setUp(() {
    store = MemorySecretStore();
    clock = FixedClock(DateTime(2026, 11, 4, 9));
    registry = ProfileRegistry(store, clock: clock);
  });

  test('several profiles on one phone, each with its own PIN and key', () async {
    final a = await registry.create(displayName: 'Hery', pin: '1111', mode: ProfileMode.personal);
    final b = await registry.create(displayName: 'Rasoa', pin: '2222', mode: ProfileMode.agent);
    expect(a.masterKey, isNot(b.masterKey));
    expect((await registry.list()).map((p) => p.displayName), ['Hery', 'Rasoa']);

    final unlocked = await registry.unlock(b.profile.id, '2222');
    expect(unlocked, isA<Unlocked>());
    expect((unlocked as Unlocked).masterKey, b.masterKey);
    expect(await registry.unlock(a.profile.id, '2222'), isA<WrongPin>());
  });

  test('the registry survives a restart (new instance, same store)', () async {
    final a = await registry.create(displayName: 'Hery', pin: '1111', mode: ProfileMode.personal);
    final again = ProfileRegistry(store, clock: clock);
    final result = await again.unlock(a.profile.id, '1111') as Unlocked;
    expect(result.masterKey, a.masterKey);
  });

  test('no health data and no PIN in the stored registry', () async {
    await registry.create(displayName: 'Hery', pin: '9876', mode: ProfileMode.personal);
    final raw = store.values['profiles_v1']!;
    expect(raw.contains('9876'), isFalse);
  });

  test('5 wrong PINs lock the profile for 30 s, then the delay grows', () async {
    final p = (await registry.create(displayName: 'Hery', pin: '1111', mode: ProfileMode.personal)).profile;
    for (var i = 1; i <= 4; i++) {
      final r = await registry.unlock(p.id, '0000') as WrongPin;
      expect(r.failures, i);
      expect(r.lockedUntil, isNull);
    }
    final fifth = await registry.unlock(p.id, '0000') as WrongPin;
    expect(fifth.lockedUntil, clock.now().add(const Duration(seconds: 30)));

    // Even the right PIN is refused while locked.
    expect(await registry.unlock(p.id, '1111'), isA<LockedOut>());

    clock.advance(const Duration(seconds: 31));
    final sixth = await registry.unlock(p.id, '0000') as WrongPin;
    expect(sixth.lockedUntil, clock.now().add(const Duration(minutes: 1)));

    clock.advance(const Duration(minutes: 2));
    expect(await registry.unlock(p.id, '1111'), isA<Unlocked>());
    expect((await registry.find(p.id))!.failedAttempts, 0);
  });

  test('changing the PIN keeps the same master key (no re-encryption)', () async {
    final created = await registry.create(displayName: 'Hery', pin: '1111', mode: ProfileMode.personal);
    await registry.changePin(created.profile.id, created.masterKey, '4321');
    expect(await registry.unlock(created.profile.id, '1111'), isA<WrongPin>());
    final r = await registry.unlock(created.profile.id, '4321') as Unlocked;
    expect(r.masterKey, created.masterKey);
  });

  test('recovery answer sets a new PIN and keeps the data key', () async {
    final created = await registry.create(
      displayName: 'Lalao',
      pin: '1111',
      mode: ProfileMode.personal,
      recoveryQuestion: 'Tanàna nahaterahako',
      recoveryAnswer: 'Ambositra',
    );
    expect(await registry.recover(created.profile.id, 'Antsirabe', '5555'), isA<WrongPin>());
    final r = await registry.recover(created.profile.id, '  AMBOSITRA ', '5555') as Unlocked;
    expect(r.masterKey, created.masterKey);
    expect(await registry.unlock(created.profile.id, '5555'), isA<Unlocked>());
  });

  test('a profile without both question and answer has no recovery', () async {
    final created = await registry.create(
      displayName: 'Fara',
      pin: '1111',
      mode: ProfileMode.personal,
      recoveryQuestion: 'Question',
      recoveryAnswer: '  ',
    );
    expect(created.profile.hasRecovery, isFalse);
  });

  test('invalid PIN is refused', () {
    expect(
      () => registry.create(displayName: 'X', pin: '12', mode: ProfileMode.personal),
      throwsArgumentError,
    );
  });

  test('no recovery codes: profiles saved with older codes still load, codes dropped', () {
    final json =
        ProfileInfo(
            id: 'p',
            displayName: 'Hery',
            mode: ProfileMode.personal,
            salt: const [1],
            pinVerifier: const [2],
            wrappedKeyByPin: const [3],
            createdAt: DateTime(2026),
          ).toJson()
          ..['code_verifiers'] = ['BAU=']
          ..['wrapped_keys_code'] = ['Bgc='];
    final p = ProfileInfo.fromJson(json);
    expect(p.displayName, 'Hery');
    expect(p.toJson().keys.where((k) => k.contains('code')), isEmpty);
  });

  group('fingerprint', () {
    test('off by default; on gives the key back; off removes it', () async {
      final a = await registry.create(displayName: 'Hery', pin: '1111', mode: ProfileMode.personal);
      expect(await registry.unlockWithBiometric(a.profile.id), isNull);

      await registry.enableBiometric(a.profile.id, a.masterKey);
      expect((await registry.find(a.profile.id))!.biometric, isTrue);
      final r = await registry.unlockWithBiometric(a.profile.id) as Unlocked;
      expect(r.masterKey, a.masterKey);

      await registry.disableBiometric(a.profile.id);
      expect(await registry.unlockWithBiometric(a.profile.id), isNull);
      expect(store.values.keys.any((k) => k.startsWith('bio_key_')), isFalse);
    });

    test('the fingerprint clears the failures', () async {
      final a = await registry.create(displayName: 'Hery', pin: '1111', mode: ProfileMode.personal);
      await registry.enableBiometric(a.profile.id, a.masterKey);
      await registry.unlock(a.profile.id, '0000');
      await registry.unlockWithBiometric(a.profile.id);
      expect((await registry.find(a.profile.id))!.failedAttempts, 0);
    });

    test('deleting the profile removes the stored key', () async {
      final a = await registry.create(displayName: 'Hery', pin: '1111', mode: ProfileMode.personal);
      await registry.enableBiometric(a.profile.id, a.masterKey);
      await registry.remove(a.profile.id);
      expect(store.values.keys.any((k) => k.startsWith('bio_key_')), isFalse);
    });
  });

  group('recovery by e-mail', () {
    test('set up offline, sent later, then the reset gives the key back', () async {
      final auth = FakeAuthService();
      final a = await registry.create(
        displayName: 'Hery',
        pin: '1111',
        mode: ProfileMode.personal,
        email: 'hery@exemple.mg',
      );
      await registry.prepareEmailRecovery(a.profile.id, a.masterKey);
      expect((await registry.find(a.profile.id))!.emailRecovery, EmailRecovery.pending);

      // Offline: the secret waits on the phone.
      auth.online = false;
      final secret = (await registry.pendingEmailSecret(a.profile.id))!;
      final offline = await auth.register(email: 'hery@exemple.mg', profileId: a.profile.id, secret: secret);
      expect(offline.error, AuthError.offline);

      // Online: account created, secret sent, nothing left on the phone.
      auth.online = true;
      expect(
        (await auth.register(email: 'hery@exemple.mg', profileId: a.profile.id, secret: secret)).isOk,
        isTrue,
      );
      await registry.markEmailActive(a.profile.id);
      expect(await registry.pendingEmailSecret(a.profile.id), isNull);
      expect((await registry.find(a.profile.id))!.emailRecovery, EmailRecovery.active);

      // Forgotten PIN: reset link, new password, secret read, new PIN.
      expect((await auth.sendPasswordReset('hery@exemple.mg')).isOk, isTrue);
      auth.chooseNewPassword('hery@exemple.mg', 'nouveau-mdp');
      expect(
        (await auth.readSecret(email: 'hery@exemple.mg', password: 'mauvais', profileId: a.profile.id)).error,
        AuthError.wrongPassword,
      );
      final read = await auth.readSecret(
        email: 'hery@exemple.mg',
        password: 'nouveau-mdp',
        profileId: a.profile.id,
      );
      final r = await registry.recoverWithEmailSecret(a.profile.id, read.value!, '7777') as Unlocked;
      expect(r.masterKey, a.masterKey);
      expect(await registry.unlock(a.profile.id, '7777'), isA<Unlocked>());
    });

    test('a wrong secret counts like a wrong PIN', () async {
      final a = await registry.create(
        displayName: 'Hery',
        pin: '1111',
        mode: ProfileMode.personal,
        email: 'h@e.mg',
      );
      await registry.prepareEmailRecovery(a.profile.id, a.masterKey);
      expect(
        await registry.recoverWithEmailSecret(a.profile.id, List.filled(32, 1), '7777'),
        isA<WrongPin>(),
      );
      expect((await registry.find(a.profile.id))!.failedAttempts, 1);
    });

    test('an address already used is to confirm; the secret is kept until then', () async {
      final auth = FakeAuthService()..passwords['h@e.mg'] = 'x';
      final a = await registry.create(
        displayName: 'Hery',
        pin: '1111',
        mode: ProfileMode.personal,
        email: 'h@e.mg',
      );
      await registry.prepareEmailRecovery(a.profile.id, a.masterKey);
      final secret = (await registry.pendingEmailSecret(a.profile.id))!;
      final result = await auth.register(email: 'h@e.mg', profileId: a.profile.id, secret: secret);
      expect(result.error, AuthError.emailInUse);
      await registry.markEmailToConfirm(a.profile.id);
      expect((await registry.find(a.profile.id))!.emailRecovery, EmailRecovery.toConfirm);
      expect(await registry.pendingEmailSecret(a.profile.id), secret);
    });

    test('the state survives a restart; deleting the profile removes the secret', () async {
      final a = await registry.create(
        displayName: 'Hery',
        pin: '1111',
        mode: ProfileMode.personal,
        email: 'h@e.mg',
      );
      await registry.prepareEmailRecovery(a.profile.id, a.masterKey);
      final again = await ProfileRegistry(store, clock: clock).find(a.profile.id);
      expect(again!.emailRecovery, EmailRecovery.pending);
      expect(again.hasEmailRecovery, isTrue);
      await registry.remove(a.profile.id);
      expect(store.values.keys.any((k) => k.startsWith('email_secret_')), isFalse);
    });
  });
}
