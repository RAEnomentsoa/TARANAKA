import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/db/app_database.dart';
import '../core/security/pin_crypto.dart';
import '../core/security/profile.dart';
import '../core/security/profile_registry.dart';
import 'app_services.dart';

/// First launch: language → profile type → consent → profile creation.
enum SessionStage {
  loading,
  chooseLanguage,
  chooseProfileType,
  consent,
  createFirstProfile,
  locked,
  unlocked,
}

class ActiveProfile {
  ActiveProfile(this.info, this.db);

  ProfileInfo info;
  final AppDatabase db;
}

/// Who is using the phone right now, and whether the app is locked.
class SessionController extends ChangeNotifier {
  SessionController(this.services);

  final AppServices services;

  /// Spec §8: automatic lock after 2 minutes without activity.
  static const Duration inactivityTimeout = Duration(minutes: 2);
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

  List<ProfileInfo> _profiles = const [];
  List<ProfileInfo> get profiles => _profiles;

  ActiveProfile? _active;
  ActiveProfile? get active => _active;

  DateTime _lastActivity = DateTime.now();

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

  void _refreshStage() {
    if (_active != null) {
      _stage = SessionStage.unlocked;
    } else if (_languageCode == null) {
      _stage = SessionStage.chooseLanguage;
    } else if (_profiles.isEmpty && _firstProfileMode == null) {
      _stage = SessionStage.chooseProfileType;
    } else if (!_consent) {
      _stage = SessionStage.consent;
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
    _active = ActiveProfile(unlocked.profile, db);
    _profiles = await services.registry.list();
    markActivity();
    _refreshStage();
  }

  Future<ProfileInfo> createProfile({
    required String displayName,
    required String pin,
    required ProfileMode mode,
    String? recoveryQuestion,
    String? recoveryAnswer,
    Future<void> Function(AppDatabase db)? prepare,
  }) async {
    final unlocked = await services.registry.create(
      displayName: displayName,
      pin: pin,
      mode: mode,
      recoveryQuestion: recoveryQuestion,
      recoveryAnswer: recoveryAnswer,
    );
    _firstProfileMode = null;
    await _activate(unlocked, prepare: prepare);
    return unlocked.profile;
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

  void markActivity() => _lastActivity = DateTime.now();

  /// Called by a timer and when the app comes back to the foreground.
  Future<bool> lockIfIdle([DateTime? now]) async {
    if (_active == null) return false;
    if ((now ?? DateTime.now()).difference(_lastActivity) < inactivityTimeout) return false;
    await lock();
    return true;
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
    _profiles = await services.registry.list();
    _refreshStage();
  }

  /// Notifies listeners after a change in the active profile's data.
  void touch() => notifyListeners();
}
