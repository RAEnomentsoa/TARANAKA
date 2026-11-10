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
    String? email,
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
    final mail = email?.trim();
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
      email: mail == null || mail.isEmpty ? null : mail,
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

  /// Forgotten PIN, personal mode: checks the answer to the secret question
  /// and gives back the master key, without changing anything else. Wrong
  /// answers count like wrong PINs (same lockout). Checked before the new PIN
  /// is asked, so a typo does not make the user type it twice for nothing.
  Future<UnlockResult> checkAnswer(String profileId, String answer) async {
    final profile = (await find(profileId))!;
    final now = _clock.now();
    if (!profile.hasRecovery) throw StateError('no recovery question');
    if (profile.lockedUntil != null && now.isBefore(profile.lockedUntil!)) {
      return LockedOut(profile.lockedUntil!);
    }
    final secret = await _deviceSecret();
    final normalised = 'answer:${PinCrypto.normaliseAnswer(answer)}';
    if (!PinCrypto.sameBytes(_crypto.verifier(secret, profile.salt, normalised), profile.recoveryVerifier!)) {
      return _fail(profile, now);
    }
    return Unlocked(profile, _crypto.unwrap(secret, profile.salt, normalised, profile.wrappedKeyByRecovery!));
  }

  /// Forgotten PIN: the answer gives back the master key, then a new PIN is
  /// set (the data are kept).
  Future<UnlockResult> recover(String profileId, String answer, String newPin) async {
    final check = await checkAnswer(profileId, answer);
    if (check is! Unlocked) return check;
    await changePin(profileId, check.masterKey, newPin);
    return Unlocked((await find(profileId))!, check.masterKey);
  }

  /// Sets or replaces the secret question of an open profile. Only a verifier
  /// of the answer and the master key wrapped by it are kept, on this phone:
  /// the answer itself is never stored nor sent.
  Future<void> setRecoveryQuestion(
    String profileId,
    Uint8List masterKey,
    String question,
    String answer,
  ) async {
    if (question.trim().isEmpty || answer.trim().isEmpty) {
      throw ArgumentError('question and answer are required');
    }
    final profile = (await find(profileId))!;
    final secret = await _deviceSecret();
    final normalised = 'answer:${PinCrypto.normaliseAnswer(answer)}';
    await _replace(
      profile.copyWith(
        recoveryQuestion: question.trim(),
        recoveryVerifier: _crypto.verifier(secret, profile.salt, normalised),
        wrappedKeyByRecovery: _crypto.wrap(secret, profile.salt, normalised, masterKey),
      ),
    );
  }

  /// A wrong PIN or answer: one more failure, and the delay of the
  /// lockout policy (from the 5th failure).
  Future<WrongPin> _fail(ProfileInfo profile, DateTime now) async {
    final failures = profile.failedAttempts + 1;
    final delay = lockout.delayAfter(failures);
    final until = delay == Duration.zero ? null : now.add(delay);
    await _replace(profile.copyWith(failedAttempts: failures, lockedUntil: until, clearLock: until == null));
    return WrongPin(failures: failures, lockedUntil: until);
  }

  // ------------------------------------------------------------ fingerprint
  //
  // The master key is kept in the Keystore-backed store and read only after
  // the phone confirmed the fingerprint (local_auth). Turning it off deletes
  // that copy: the PIN stays the only way in.

  static String _bioKey(String profileId) => 'bio_key_$profileId';

  Future<void> enableBiometric(String profileId, Uint8List masterKey) async {
    await _store.write(_bioKey(profileId), base64Encode(masterKey));
    await _replace((await find(profileId))!.copyWith(biometric: true));
  }

  Future<void> disableBiometric(String profileId) async {
    await _store.delete(_bioKey(profileId));
    final profile = await find(profileId);
    if (profile != null) await _replace(profile.copyWith(biometric: false));
  }

  /// To call only after the fingerprint was confirmed. Resets the failures.
  Future<UnlockResult?> unlockWithBiometric(String profileId) async {
    final profile = await find(profileId);
    if (profile == null || !profile.biometric) return null;
    final raw = await _store.read(_bioKey(profileId));
    if (raw == null) return null;
    final unlocked = profile.copyWith(failedAttempts: 0, clearLock: true);
    if (profile.failedAttempts != 0 || profile.lockedUntil != null) await _replace(unlocked);
    return Unlocked(unlocked, Uint8List.fromList(base64Decode(raw)));
  }

  // ---------------------------------------------------------- e-mail (Firebase)
  //
  // A random secret wraps one more copy of the master key. The secret goes to
  // Firestore (readable only by the Firebase account of the e-mail address);
  // until it is sent, it waits in the Keystore-backed store.

  static String _emailSecretKey(String profileId) => 'email_secret_$profileId';
  static String _emailMaterial(List<int> secret) => 'email:${base64Encode(secret)}';

  /// Sets up the recovery by e-mail ([email] may replace the address): wraps
  /// the key with a new secret, kept on the phone until it is sent.
  Future<void> prepareEmailRecovery(String profileId, Uint8List masterKey, {String? email}) async {
    final profile = (await find(profileId))!;
    final mail = (email ?? profile.email)?.trim();
    if (mail == null || mail.isEmpty) throw StateError('no e-mail address');
    final device = await _deviceSecret();
    final secret = _crypto.randomBytes();
    final material = _emailMaterial(secret);
    await _store.write(_emailSecretKey(profileId), base64Encode(secret));
    await _replace(
      profile.copyWith(
        email: mail,
        emailVerifier: _crypto.verifier(device, profile.salt, material),
        wrappedKeyByEmail: _crypto.wrap(device, profile.salt, material, masterKey),
        emailRecovery: EmailRecovery.pending,
      ),
    );
  }

  /// The secret not yet sent to Firestore (null once sent).
  Future<Uint8List?> pendingEmailSecret(String profileId) async {
    final raw = await _store.read(_emailSecretKey(profileId));
    return raw == null ? null : Uint8List.fromList(base64Decode(raw));
  }

  /// The secret is in Firestore: the recovery by e-mail works.
  Future<void> markEmailActive(String profileId) async {
    await _store.delete(_emailSecretKey(profileId));
    final profile = await find(profileId);
    if (profile != null) await _replace(profile.copyWith(emailRecovery: EmailRecovery.active));
  }

  /// The address already has a Firebase account: to confirm in Paramètres.
  Future<void> markEmailToConfirm(String profileId) async {
    final profile = await find(profileId);
    if (profile != null) await _replace(profile.copyWith(emailRecovery: EmailRecovery.toConfirm));
  }

  /// Forgotten PIN: the secret read from Firestore (after the sign-in with the
  /// password chosen through the reset link) gives back the master key.
  Future<UnlockResult> recoverWithEmailSecret(String profileId, List<int> secret, String newPin) async {
    final profile = (await find(profileId))!;
    final now = _clock.now();
    if (!profile.hasEmailRecovery) throw StateError('no e-mail recovery');
    if (profile.lockedUntil != null && now.isBefore(profile.lockedUntil!)) {
      return LockedOut(profile.lockedUntil!);
    }
    final device = await _deviceSecret();
    final material = _emailMaterial(secret);
    if (!PinCrypto.sameBytes(_crypto.verifier(device, profile.salt, material), profile.emailVerifier!)) {
      return _fail(profile, now);
    }
    final master = _crypto.unwrap(device, profile.salt, material, profile.wrappedKeyByEmail!);
    await changePin(profileId, master, newPin);
    return Unlocked((await find(profileId))!, master);
  }

  Future<void> remove(String profileId) async {
    await _store.delete(_bioKey(profileId));
    await _store.delete(_emailSecretKey(profileId));
    await _save([...await list()]..removeWhere((p) => p.id == profileId));
  }
}
