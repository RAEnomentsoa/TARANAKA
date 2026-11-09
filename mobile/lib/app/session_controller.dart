import 'dart:convert';
import 'dart:io';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/auth/auth_service.dart';

import '../core/db/app_database.dart';
import '../core/platform/local_reminders.dart';
import '../features/child/application/vaccine_reminders_sync.dart';
import '../core/security/pin_crypto.dart';
import '../core/security/profile.dart';
import '../core/security/profile_registry.dart';
import 'app_services.dart';

/// First launch: language → welcome → profile type → profile creation →
/// consent.
enum SessionStage {
  loading,
  chooseLanguage,

  /// "Bienvenue sur TARANAKA": what the app is for, then "Commencer".
  welcome,
  chooseProfileType,
  createFirstProfile,

  /// A profile is open but the consent is not accepted yet.
  consent,
  locked,
  unlocked,
}

class ActiveProfile {
  ActiveProfile(this.info, this.db, this.masterKey);

  ProfileInfo info;
  final AppDatabase db;

  /// Key of the open database, in memory only while unlocked (to enable the
  /// fingerprint or give a new recovery code).
  final Uint8List masterKey;
}

/// Who is using the phone right now, and whether the app is locked.
class SessionController extends ChangeNotifier {
  SessionController(this.services);

  final AppServices services;

  /// No automatic lock after a delay of inactivity: the app locks only when
  /// the phone screen turns off, when the user taps "Verrouiller", or when
  /// the app is closed (the profile key lives in memory only).
  static const _prefsKey = 'app_prefs_v1';

  SessionStage _stage = SessionStage.loading;
  SessionStage get stage => _stage;

  String? _languageCode;
  String? get languageCode => _languageCode;

  bool _consent = false;

  /// Profile type chosen on first launch ("Personnel" or "Agent de santé"),
  /// before any profile exists. Kept in memory only: nothing is stored yet.
  ProfileMode? _firstProfileMode;
  ProfileMode? get firstProfileMode => _firstProfileMode;

  /// "Commencer" tapped on the welcome screen (memory only: the welcome comes
  /// back at the next launch as long as no profile exists).
  bool _welcomeDone = false;

  List<ProfileInfo> _profiles = const [];
  List<ProfileInfo> get profiles => _profiles;

  ActiveProfile? _active;
  ActiveProfile? get active => _active;

  Future<void> init() async {
    await services.config.load();
    final raw = await services.secrets.read(_prefsKey);
    if (raw != null) {
      final prefs = (jsonDecode(raw) as Map).cast<String, Object?>();
      _languageCode = prefs['language'] as String?;
      _consent = prefs['consent_v1'] == true;
    }
    _profiles = await services.registry.list();
    _refreshStage();
  }

  Future<void> _savePrefs() =>
      services.secrets.write(_prefsKey, jsonEncode({'language': _languageCode, 'consent_v1': _consent}));

  /// First launch: language → welcome → profile type → profile creation →
  /// consent, shown right after the profile is created, before anything else
  /// of the app (and again at each opening until it is accepted).
  void _refreshStage() {
    if (_active != null) {
      _stage = _consent ? SessionStage.unlocked : SessionStage.consent;
    } else if (_languageCode == null) {
      _stage = SessionStage.chooseLanguage;
    } else if (_profiles.isEmpty && !_welcomeDone && _firstProfileMode == null) {
      _stage = SessionStage.welcome;
    } else if (_profiles.isEmpty && _firstProfileMode == null) {
      _stage = SessionStage.chooseProfileType;
    } else if (_profiles.isEmpty) {
      _stage = SessionStage.createFirstProfile;
    } else {
      _stage = SessionStage.locked;
    }
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    await _savePrefs();
    _refreshStage();
  }

  /// "Commencer" on the welcome screen: on to the profile type.
  void startFromWelcome() {
    _welcomeDone = true;
    _refreshStage();
  }

  /// Back from the profile type to the welcome screen.
  void backToWelcome() {
    _welcomeDone = false;
    _refreshStage();
  }

  void chooseFirstProfileMode(ProfileMode mode) {
    _firstProfileMode = mode;
    _refreshStage();
  }

  /// Back from the profile creation to the profile type choice.
  void clearFirstProfileMode() {
    _firstProfileMode = null;
    _refreshStage();
  }

  Future<void> acceptConsent() async {
    _consent = true;
    await _savePrefs();
    _refreshStage();
  }

  Future<AppDatabase> _openDb(String profileId, Uint8List masterKey) async => AppDatabase.open(
    services.dbOpener,
    await services.profileDbPath(profileId),
    PinCrypto.passphrase(masterKey),
  );

  Future<void> _activate(Unlocked unlocked, {Future<void> Function(AppDatabase db)? prepare}) async {
    await _closeActive();
    final db = await _openDb(unlocked.profile.id, unlocked.masterKey);
    // Written before the home of the profile opens (e.g. the agent account).
    await prepare?.call(db);
    _active = ActiveProfile(unlocked.profile, db, unlocked.masterKey);
    _profiles = await services.registry.list();
    _refreshStage();
    // Recovery by e-mail set up offline: the account is created now if the
    // phone is online (in the background, a few Ko).
    if (unlocked.profile.emailRecovery == EmailRecovery.pending) unawaited(syncEmailRecovery());
  }

  Future<ProfileInfo> createProfile({
    required String displayName,
    required String pin,
    required ProfileMode mode,
    String? recoveryQuestion,
    String? recoveryAnswer,
    String? recoveryCode,
    String? email,
    Future<void> Function(AppDatabase db)? prepare,
  }) async {
    var unlocked = await services.registry.create(
      displayName: displayName,
      pin: pin,
      mode: mode,
      recoveryQuestion: recoveryQuestion,
      recoveryAnswer: recoveryAnswer,
      recoveryCode: recoveryCode,
      email: email,
    );
    if (unlocked.profile.email != null && mode == ProfileMode.personal) {
      await services.registry.prepareEmailRecovery(unlocked.profile.id, unlocked.masterKey);
      unlocked = Unlocked((await services.registry.find(unlocked.profile.id))!, unlocked.masterKey);
    }
    _firstProfileMode = null;
    await _activate(
      unlocked,
      prepare: (db) async {
        // Kept in the encrypted database, to show or download it again.
        if (recoveryCode != null) await db.setMeta(_recoveryCodeKey, recoveryCode);
        await prepare?.call(db);
      },
    );
    return unlocked.profile;
  }

  static const _recoveryCodeKey = 'recovery_code_v1';

  /// The recovery code of the open profile, or null (profile created before
  /// the codes, or a code given elsewhere).
  Future<String?> recoveryCode() async => _active?.db.getMeta(_recoveryCodeKey);

  /// A new recovery code for the open profile; the previous one stops working.
  Future<String> renewRecoveryCode() async {
    final active = _active!;
    final code = PinCrypto.joinRecoveryCodes(PinCrypto().newRecoveryCodes());
    await services.registry.setRecoveryCode(active.info.id, active.masterKey, code);
    await active.db.setMeta(_recoveryCodeKey, code);
    await _refreshActiveInfo();
    return code;
  }

  /// "Code oublié ?" with the recovery code: new PIN, profile opened.
  Future<UnlockResult> recoverWithCode(String profileId, String code, String newPin) async {
    final result = await services.registry.recoverWithCode(profileId, code, newPin);
    if (result is Unlocked) {
      await _activate(result);
    } else {
      _profiles = await services.registry.list();
      notifyListeners();
    }
    return result;
  }

  // ------------------------------------------------- recovery by e-mail

  /// The sync in progress, shared: a second call waits for the same result
  /// (never two accounts nor two secrets at the same time).
  Future<AuthError?>? _emailSync;

  /// Creates the Firebase account of the open profile (recovery "pending")
  /// and stores its secret. Null when done; otherwise why it waits.
  Future<AuthError?> syncEmailRecovery() {
    final running = _emailSync;
    if (running != null) return running;
    final sync = _syncEmail().whenComplete(() => _emailSync = null);
    _emailSync = sync;
    return sync;
  }

  Future<AuthError?> _syncEmail() async {
    final active = _active;
    if (active == null || active.info.emailRecovery != EmailRecovery.pending) return null;
    final email = active.info.email;
    if (email == null || email.isEmpty) return AuthError.invalidEmail;
    try {
      final id = active.info.id;
      var secret = await services.registry.pendingEmailSecret(id);
      if (secret == null) {
        await services.registry.prepareEmailRecovery(id, active.masterKey);
        secret = (await services.registry.pendingEmailSecret(id))!;
      }
      final result = await services.auth.register(email: email, profileId: id, secret: secret);
      // The profile may have been locked or changed meanwhile.
      if (_active?.info.id != id) return result.error;
      if (result.isOk) {
        await services.registry.markEmailActive(id);
      } else if (result.error == AuthError.emailInUse) {
        await services.registry.markEmailToConfirm(id);
      }
      await _refreshActiveInfo();
      return result.error;
    } on Object catch (e) {
      debugPrint('E-mail recovery: $e');
      return AuthError.unknown;
    }
  }

  /// Turns on the recovery by e-mail for the open profile (an older one, or
  /// a new address), then tries to create the account at once.
  Future<AuthError?> enableEmailRecovery(String email) async {
    // A sync still running uses the current secret: wait for it first.
    await _emailSync;
    final active = _active;
    if (active == null) return AuthError.unknown;
    try {
      await services.registry.prepareEmailRecovery(active.info.id, active.masterKey, email: email.trim());
    } on Object catch (e) {
      debugPrint('E-mail recovery: $e');
      return AuthError.unknown;
    }
    await _refreshActiveInfo();
    return syncEmailRecovery();
  }

  /// Sends the standard Firebase reset e-mail to the address of [profileId].
  Future<AuthResult<void>> sendPasswordReset(String profileId) async {
    final profile = (await services.registry.find(profileId))!;
    return services.auth.sendPasswordReset(profile.email!);
  }

  /// The address already had an account: with the password chosen through
  /// the reset link, the secret of the open profile is stored there.
  Future<AuthError?> confirmEmailRecovery(String password) async {
    final active = _active!;
    final id = active.info.id;
    var secret = await services.registry.pendingEmailSecret(id);
    if (secret == null) {
      await services.registry.prepareEmailRecovery(id, active.masterKey);
      await services.registry.markEmailToConfirm(id);
      secret = (await services.registry.pendingEmailSecret(id))!;
    }
    final result = await services.auth.attach(
      email: active.info.email!,
      password: password,
      profileId: id,
      secret: secret,
    );
    if (result.isOk) await services.registry.markEmailActive(id);
    await _refreshActiveInfo();
    return result.error;
  }

  /// "Code oublié ?" by e-mail, step 1: signs in with the password chosen
  /// through the link and reads the secret of the profile.
  Future<AuthResult<Uint8List>> fetchEmailSecret(String profileId, String password) async {
    final profile = (await services.registry.find(profileId))!;
    return services.auth.readSecret(email: profile.email!, password: password, profileId: profileId);
  }

  /// Step 2: the new PIN; the profile opens with its data.
  Future<UnlockResult> recoverWithEmailSecret(String profileId, List<int> secret, String newPin) async {
    final result = await services.registry.recoverWithEmailSecret(profileId, secret, newPin);
    if (result is Unlocked) {
      await _activate(result);
    } else {
      _profiles = await services.registry.list();
      notifyListeners();
    }
    return result;
  }

  /// Unlock after the fingerprint was confirmed by the phone.
  Future<bool> unlockWithBiometric(String profileId) async {
    final result = await services.registry.unlockWithBiometric(profileId);
    if (result is! Unlocked) return false;
    await _activate(result);
    return true;
  }

  /// Turns the fingerprint unlock of the open profile on or off.
  Future<void> setBiometric(bool enabled) async {
    final active = _active!;
    enabled
        ? await services.registry.enableBiometric(active.info.id, active.masterKey)
        : await services.registry.disableBiometric(active.info.id);
    await _refreshActiveInfo();
  }

  Future<void> _refreshActiveInfo() async {
    _profiles = await services.registry.list();
    final active = _active;
    if (active != null) active.info = (await services.registry.find(active.info.id)) ?? active.info;
    notifyListeners();
  }

  Future<UnlockResult> unlock(String profileId, String pin) async {
    final result = await services.registry.unlock(profileId, pin);
    if (result is Unlocked) {
      await _activate(result);
    } else {
      _profiles = await services.registry.list();
      notifyListeners();
    }
    return result;
  }

  Future<UnlockResult> recover(String profileId, String answer, String newPin) async {
    final result = await services.registry.recover(profileId, answer, newPin);
    if (result is Unlocked) {
      await _activate(result);
    } else {
      _profiles = await services.registry.list();
      notifyListeners();
    }
    return result;
  }

  /// Checks the current PIN (a wrong one counts as a failed attempt), then
  /// re-wraps the key under the new PIN.
  Future<UnlockResult> changePin(String currentPin, String newPin) async {
    final active = _active!;
    final check = await services.registry.unlock(active.info.id, currentPin);
    if (check is Unlocked) {
      await services.registry.changePin(active.info.id, check.masterKey, newPin);
    }
    _profiles = await services.registry.list();
    notifyListeners();
    return check;
  }

  Future<void> _closeActive() async {
    final active = _active;
    _active = null;
    await active?.db.close();
  }

  Future<void> lock() async {
    if (_active == null) return;
    await _closeActive();
    _refreshStage();
  }

  /// Deletes a profile and its database file ("Effacer toutes mes données",
  /// or a forgotten PIN without recovery).
  Future<void> deleteProfile(String profileId) async {
    if (_active?.info.id == profileId) await _closeActive();
    final path = await services.profileDbPath(profileId);
    await services.dbOpener.delete(path);
    for (final suffix in ['-journal', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
    await services.registry.remove(profileId);
    // Its reminders go with it.
    await LocalReminders.cancelGroup(vaccineReminderGroup(profileId));
    _profiles = await services.registry.list();
    _refreshStage();
  }

  /// Notifies listeners after a change in the active profile's data.
  void touch() => notifyListeners();
}
