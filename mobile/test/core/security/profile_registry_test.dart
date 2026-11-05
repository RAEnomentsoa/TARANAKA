import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/security/profile.dart';
import 'package:taranaka/core/security/profile_registry.dart';
import 'package:taranaka/core/security/secret_store.dart';
import 'package:taranaka/core/util/clock.dart';

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
}
