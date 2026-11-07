import 'dart:convert';
import 'dart:typed_data';

import '../util/clock.dart';
import '../util/ids.dart';
import 'pin_crypto.dart';
import 'pin_lockout.dart';
import 'profile.dart';
import 'secret_store.dart';

sealed class UnlockResult {
  const UnlockResult();
}

class Unlocked extends UnlockResult {
  const Unlocked(this.profile, this.masterKey);
  final ProfileInfo profile;
  final Uint8List masterKey;
}

class WrongPin extends UnlockResult {
  const WrongPin({required this.failures, this.lockedUntil});
  final int failures;
  final DateTime? lockedUntil;
}

class LockedOut extends UnlockResult {
  const LockedOut(this.until);
  final DateTime until;
}

/// The profiles of this phone (spec §1 P7: a shared phone is the normal case).
///
/// Stored in the Keystore-backed [SecretStore]. Holds names and wrapped keys,
/// never health data.
class ProfileRegistry {
  ProfileRegistry(this._store, {PinCrypto? crypto, Clock? clock, this.lockout = const PinLockoutPolicy()})
    : _crypto = crypto ?? PinCrypto(),
      _clock = clock ?? const SystemClock();

  final SecretStore _store;
  final PinCrypto _crypto;
  final Clock _clock;
  final PinLockoutPolicy lockout;

  static const _profilesKey = 'profiles_v1';
  static const _deviceSecretKey = 'device_secret_v1';

  List<ProfileInfo>? _cache;

  Future<List<ProfileInfo>> list() async {
    if (_cache != null) return List.unmodifiable(_cache!);
    final raw = await _store.read(_profilesKey);
    final decoded = raw == null ? const <Object?>[] : jsonDecode(raw) as List<Object?>;
    _cache = decoded.map((e) => ProfileInfo.fromJson((e! as Map).cast<String, Object?>())).toList();
    return List.unmodifiable(_cache!);
  }

  Future<ProfileInfo?> find(String id) async {
    for (final p in await list()) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _save(List<ProfileInfo> profiles) async {
    _cache = profiles;
    await _store.write(_profilesKey, jsonEncode(profiles.map((p) => p.toJson()).toList()));
  }

  Future<void> _replace(ProfileInfo profile) async {
    final profiles = [...await list()];
    final index = profiles.indexWhere((p) => p.id == profile.id);
    profiles[index] = profile;
    await _save(profiles);
  }

  Future<Uint8List> _deviceSecret() async {
    final existing = await _store.read(_deviceSecretKey);
    if (existing != null) return base64Decode(existing);
    final secret = _crypto.randomBytes();
    await _store.write(_deviceSecretKey, base64Encode(secret));
    return secret;
  }

  /// Creates a profile and returns it with its new master key (already unlocked).
  Future<Unlocked> create({
    required String displayName,
    required String pin,
    required ProfileMode mode,
    String? recoveryQuestion,
    String? recoveryAnswer,
  }) async {
    if (!PinCrypto.isValidPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'must be 4 digits');
    }
    final secret = await _deviceSecret();
    final salt = _crypto.randomBytes(16);
    final master = _crypto.randomBytes();
    final withRecovery =
        (recoveryQuestion?.trim().isNotEmpty ?? false) && (recoveryAnswer?.trim().isNotEmpty ?? false);
    final answer = withRecovery ? PinCrypto.normaliseAnswer(recoveryAnswer!) : null;
    final profile = ProfileInfo(
      id: newUuid(),
      displayName: displayName.trim(),
      mode: mode,
      salt: salt,
      pinVerifier: _crypto.verifier(secret, salt, pin),
      wrappedKeyByPin: _crypto.wrap(secret, salt, pin, master),
      createdAt: _clock.now(),
      recoveryQuestion: withRecovery ? recoveryQuestion!.trim() : null,
      recoveryVerifier: withRecovery ? _crypto.verifier(secret, salt, 'answer:$answer') : null,
      wrappedKeyByRecovery: withRecovery ? _crypto.wrap(secret, salt, 'answer:$answer', master) : null,
    );
    await _save([...await list(), profile]);
    return Unlocked(profile, master);
  }

  Future<UnlockResult> unlock(String profileId, String pin) async {
    final profile = (await find(profileId))!;
    final now = _clock.now();
    if (profile.lockedUntil != null && now.isBefore(profile.lockedUntil!)) {
      return LockedOut(profile.lockedUntil!);
    }
    final secret = await _deviceSecret();
    if (!PinCrypto.sameBytes(_crypto.verifier(secret, profile.salt, pin), profile.pinVerifier)) {
      final failures = profile.failedAttempts + 1;
      final delay = lockout.delayAfter(failures);
      final until = delay == Duration.zero ? null : now.add(delay);
      await _replace(
        profile.copyWith(failedAttempts: failures, lockedUntil: until, clearLock: until == null),
      );
      return WrongPin(failures: failures, lockedUntil: until);
    }
    final unlocked = profile.copyWith(failedAttempts: 0, clearLock: true);
    if (profile.failedAttempts != 0 || profile.lockedUntil != null) await _replace(unlocked);
    return Unlocked(unlocked, _crypto.unwrap(secret, profile.salt, pin, profile.wrappedKeyByPin));
  }

  /// Re-wraps the master key under a new PIN (the database is not re-encrypted).
  Future<void> changePin(String profileId, Uint8List masterKey, String newPin) async {
    if (!PinCrypto.isValidPin(newPin)) {
      throw ArgumentError.value(newPin, 'newPin', 'must be 4 digits');
    }
    final profile = (await find(profileId))!;
    final secret = await _deviceSecret();
    await _replace(
      profile.copyWith(
        pinVerifier: _crypto.verifier(secret, profile.salt, newPin),
        wrappedKeyByPin: _crypto.wrap(secret, profile.salt, newPin, masterKey),
        failedAttempts: 0,
        clearLock: true,
      ),
    );
  }

  /// Forgotten PIN, personal mode: the recovery answer gives back the master
  /// key, then a new PIN is set. Wrong answers count like wrong PINs.
  Future<UnlockResult> recover(String profileId, String answer, String newPin) async {
    final profile = (await find(profileId))!;
    final now = _clock.now();
    if (!profile.hasRecovery) throw StateError('no recovery question');
    if (profile.lockedUntil != null && now.isBefore(profile.lockedUntil!)) {
      return LockedOut(profile.lockedUntil!);
    }
    final secret = await _deviceSecret();
    final normalised = 'answer:${PinCrypto.normaliseAnswer(answer)}';
    if (!PinCrypto.sameBytes(_crypto.verifier(secret, profile.salt, normalised), profile.recoveryVerifier!)) {
      final failures = profile.failedAttempts + 1;
      final delay = lockout.delayAfter(failures);
      final until = delay == Duration.zero ? null : now.add(delay);
      await _replace(
        profile.copyWith(failedAttempts: failures, lockedUntil: until, clearLock: until == null),
      );
      return WrongPin(failures: failures, lockedUntil: until);
    }
    final master = _crypto.unwrap(secret, profile.salt, normalised, profile.wrappedKeyByRecovery!);
    await changePin(profileId, master, newPin);
    return Unlocked((await find(profileId))!, master);
  }

  Future<void> remove(String profileId) async {
    await _save([...await list()]..removeWhere((p) => p.id == profileId));
  }
}
