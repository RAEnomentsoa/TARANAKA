import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Why a Firebase call did not work, in terms the screens can explain.
enum AuthError {
  /// No Internet (or Firebase unreachable): try again later.
  offline,

  /// The address already has a Firebase account.
  emailInUse,

  /// Wrong e-mail or password.
  wrongPassword,

  /// Too many tries: Firebase blocks for a while.
  tooManyRequests,

  /// The address is not valid for Firebase.
  invalidEmail,

  /// Firebase is not set up (provider off, Firestore missing, rules).
  notConfigured,

  /// No recovery secret stored for this profile.
  noSecret,

  unknown,
}

/// A result or an [AuthError].
class AuthResult<T> {
  const AuthResult.ok(this.value) : error = null;
  const AuthResult.failed(AuthError this.error) : value = null;

  final T? value;
  final AuthError? error;

  bool get isOk => error == null;
}

/// The online account behind the recovery by e-mail.
///
/// Firebase Auth only proves that the person owns the e-mail address: health
/// data never leaves the phone. Each profile keeps, in Firestore, a random
/// secret that unwraps a copy of its key (see ProfileRegistry); only the
/// account of that address can read it.
///
/// - [register]: at the profile creation, an account with a random password
///   nobody knows (no password to invent nor remember).
/// - Forgotten PIN: [sendPasswordReset] sends the standard Firebase e-mail;
///   its link opens a Firebase page where the person chooses a password;
///   [readSecret] then signs in with it and reads the secret.
abstract class AuthService {
  /// Creates the account and stores [secret] for [profileId].
  Future<AuthResult<void>> register({
    required String email,
    required String profileId,
    required List<int> secret,
  });

  /// Stores [secret] for [profileId] in an existing account (address already
  /// used), with the password chosen through the reset link.
  Future<AuthResult<void>> attach({
    required String email,
    required String password,
    required String profileId,
    required List<int> secret,
  });

  /// Sends the standard Firebase password reset e-mail.
  Future<AuthResult<void>> sendPasswordReset(String email);

  /// Signs in with the password chosen through the link and reads the secret
  /// of [profileId].
  Future<AuthResult<Uint8List>> readSecret({
    required String email,
    required String password,
    required String profileId,
  });
}

/// Firebase Auth + Firestore (`recovery/{uid}/profiles/{profileId}`).
/// Firebase is reached only when one of these methods is called, so the app
/// works fully offline. Signs out after each operation: no session is kept.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _authOverride = auth,
      _dbOverride = firestore;

  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _dbOverride;

  // Not touched before the first call: Firebase.initializeApp() may have
  // failed (no config) without breaking the rest of the app.
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _db {
    final db = _dbOverride ?? FirebaseFirestore.instance;
    if (!_settingsDone) {
      _settingsDone = true;
      // No local cache: offline, a write fails at once ("unavailable")
      // instead of waiting forever for the network.
      try {
        db.settings = const Settings(persistenceEnabled: false);
      } on Object {
        // Settings already set (or not changeable): keep them.
      }
    }
    return db;
  }

  bool _settingsDone = false;

  /// A Firebase call that takes longer than this is treated as offline.
  static const timeout = Duration(seconds: 25);

  DocumentReference<Map<String, dynamic>> _doc(String uid, String profileId) =>
      _db.collection('recovery').doc(uid).collection('profiles').doc(profileId);

  static String _randomPassword() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789-_!';
    final rnd = Random.secure();
    return List.generate(32, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _store(String uid, String profileId, List<int> secret) =>
      _doc(uid, profileId).set({'secret': base64Encode(secret), 'updated_at': FieldValue.serverTimestamp()});

  @override
  Future<AuthResult<void>> register({
    required String email,
    required String profileId,
    required List<int> secret,
  }) => _guard(() async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: _randomPassword());
    final user = cred.user;
    if (user == null) throw FirebaseAuthException(code: 'internal-error');
    try {
      await _store(user.uid, profileId, secret);
    } on Object {
      // Without its secret the account is useless, and its password is
      // unknown: delete it, so that "Réessayer" creates it again instead of
      // finding the address "already used".
      try {
        await user.delete();
      } on Object {
        // Left as it is: the screen will ask to confirm the address.
      }
      rethrow;
    }
  });

  @override
  Future<AuthResult<void>> attach({
    required String email,
    required String password,
    required String profileId,
    required List<int> secret,
  }) => _guard(() async {
    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    await _store(cred.user!.uid, profileId, secret);
  });

  @override
  Future<AuthResult<void>> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<AuthResult<Uint8List>> readSecret({
    required String email,
    required String password,
    required String profileId,
  }) async {
    Uint8List? secret;
    final result = await _guard(() async {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final snap = await _doc(cred.user!.uid, profileId).get();
      final raw = snap.data()?['secret'];
      if (raw is String) secret = Uint8List.fromList(base64Decode(raw));
    });
    if (!result.isOk) return AuthResult.failed(result.error!);
    return secret == null ? const AuthResult.failed(AuthError.noSecret) : AuthResult.ok(secret);
  }

  Future<AuthResult<void>> _guard(Future<void> Function() action) async {
    try {
      if (Firebase.apps.isEmpty) return const AuthResult.failed(AuthError.notConfigured);
      await action().timeout(timeout);
      return const AuthResult.ok(null);
    } on TimeoutException {
      return const AuthResult.failed(AuthError.offline);
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth: ${e.code} ${e.message}');
      return AuthResult.failed(authErrorOf(e.code, e.message));
    } on FirebaseException catch (e) {
      debugPrint('Firebase ${e.plugin}: ${e.code} ${e.message}');
      return AuthResult.failed(firestoreErrorOf(e.code, e.message));
    } on Object catch (e) {
      debugPrint('Firebase: $e');
      return AuthResult.failed(_fromMessage(e.toString()) ?? AuthError.unknown);
    } finally {
      await _signOut();
    }
  }

  Future<void> _signOut() async {
    try {
      if (Firebase.apps.isNotEmpty && _auth.currentUser != null) await _auth.signOut();
    } on Object {
      // Nothing to do: the next sign-in replaces the session anyway.
    }
  }

  /// Firebase Auth codes, as the screens explain them. Some errors come as
  /// "internal-error" / "unknown" with the reason only in the message.
  @visibleForTesting
  static AuthError authErrorOf(String code, [String? message]) => switch (code) {
    'network-request-failed' || 'web-network-request-failed' => AuthError.offline,
    'email-already-in-use' || 'credential-already-in-use' => AuthError.emailInUse,
    'wrong-password' ||
    'invalid-credential' ||
    'user-not-found' ||
    'invalid-login-credentials' ||
    'user-mismatch' ||
    'missing-password' ||
    'user-disabled' => AuthError.wrongPassword,
    'too-many-requests' || 'quota-exceeded' => AuthError.tooManyRequests,
    'invalid-email' || 'missing-email' => AuthError.invalidEmail,
    'operation-not-allowed' ||
    'configuration-not-found' ||
    'app-not-authorized' ||
    'admin-restricted-operation' ||
    'invalid-api-key' ||
    'api-key-not-valid' ||
    'app-not-installed' => AuthError.notConfigured,
    _ => _fromMessage(message) ?? AuthError.unknown,
  };

  /// Firestore (and Firebase core) codes.
  @visibleForTesting
  static AuthError firestoreErrorOf(String code, [String? message]) => switch (code) {
    'unavailable' || 'deadline-exceeded' || 'network-request-failed' => AuthError.offline,
    'permission-denied' ||
    'not-found' ||
    'failed-precondition' ||
    'no-app' ||
    'unauthenticated' ||
    'unimplemented' => AuthError.notConfigured,
    'resource-exhausted' => AuthError.tooManyRequests,
    _ => _fromMessage(message) ?? AuthError.unknown,
  };

  static AuthError? _fromMessage(String? message) {
    final m = (message ?? '').toUpperCase();
    if (m.isEmpty) return null;
    if (m.contains('CONFIGURATION_NOT_FOUND') ||
        m.contains('OPERATION_NOT_ALLOWED') ||
        m.contains('API KEY') ||
        m.contains('API_KEY') ||
        m.contains('PERMISSION_DENIED') ||
        m.contains('NO FIREBASE APP')) {
      return AuthError.notConfigured;
    }
    if (m.contains('EMAIL_EXISTS')) return AuthError.emailInUse;
    if (m.contains('INVALID_EMAIL')) return AuthError.invalidEmail;
    if (m.contains('TOO_MANY_ATTEMPTS')) return AuthError.tooManyRequests;
    if (m.contains('NETWORK') ||
        m.contains('UNREACHABLE') ||
        m.contains('TIMEOUT') ||
        m.contains('UNAVAILABLE')) {
      return AuthError.offline;
    }
    return null;
  }
}
