import 'dart:typed_data';

import 'package:taranaka/core/auth/auth_service.dart';

/// In memory, for tests: accounts by e-mail, a password per account.
class FakeAuthService implements AuthService {
  final passwords = <String, String>{};
  final secrets = <String, Map<String, Uint8List>>{};
  final resets = <String>[];
  bool online = true;

  /// What the person types on the Firebase page opened by the link.
  void chooseNewPassword(String email, String password) => passwords[email] = password;

  @override
  Future<AuthResult<void>> register({
    required String email,
    required String profileId,
    required List<int> secret,
  }) async {
    if (!online) return const AuthResult.failed(AuthError.offline);
    if (passwords.containsKey(email)) return const AuthResult.failed(AuthError.emailInUse);
    passwords[email] = '(random)';
    (secrets[email] ??= {})[profileId] = Uint8List.fromList(secret);
    return const AuthResult.ok(null);
  }

  @override
  Future<AuthResult<void>> attach({
    required String email,
    required String password,
    required String profileId,
    required List<int> secret,
  }) async {
    if (!online) return const AuthResult.failed(AuthError.offline);
    if (passwords[email] != password) return const AuthResult.failed(AuthError.wrongPassword);
    (secrets[email] ??= {})[profileId] = Uint8List.fromList(secret);
    return const AuthResult.ok(null);
  }

  @override
  Future<AuthResult<void>> sendPasswordReset(String email) async {
    if (!online) return const AuthResult.failed(AuthError.offline);
    resets.add(email);
    return const AuthResult.ok(null);
  }

  @override
  Future<AuthResult<Uint8List>> readSecret({
    required String email,
    required String password,
    required String profileId,
  }) async {
    if (!online) return const AuthResult.failed(AuthError.offline);
    if (passwords[email] != password) return const AuthResult.failed(AuthError.wrongPassword);
    final secret = secrets[email]?[profileId];
    return secret == null ? const AuthResult.failed(AuthError.noSecret) : AuthResult.ok(secret);
  }
}
