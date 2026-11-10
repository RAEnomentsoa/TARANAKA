import 'dart:convert';

enum ProfileMode {
  /// "Pour moi et ma famille": no account, local PIN only.
  personal,

  /// "Je suis agent de santé": named server account + local PIN.
  agent;

  static ProfileMode parse(String value) =>
      ProfileMode.values.firstWhere((m) => m.name == value, orElse: () => ProfileMode.personal);
}

/// Where the recovery by e-mail stands (Firebase Auth, see
/// core/auth/auth_service.dart).
enum EmailRecovery {
  /// No e-mail address, or recovery not set up.
  none,

  /// Set up on the phone; the Firebase account is created when online.
  pending,

  /// Firebase account created and secret stored: the recovery works.
  active,

  /// The address already has a Firebase account (other profile, reinstall):
  /// to confirm with the reset link, in Paramètres.
  toConfirm;

  static EmailRecovery parse(Object? value) =>
      EmailRecovery.values.firstWhere((s) => s.name == value, orElse: () => EmailRecovery.none);
}

/// What the device knows about a profile before it is unlocked. Holds no
/// health data: only the display name and the wrapped key material.
class ProfileInfo {
  const ProfileInfo({
    required this.id,
    required this.displayName,
    required this.mode,
    required this.salt,
    required this.pinVerifier,
    required this.wrappedKeyByPin,
    required this.createdAt,
    this.failedAttempts = 0,
    this.lockedUntil,
    this.recoveryQuestion,
    this.recoveryVerifier,
    this.wrappedKeyByRecovery,
    this.email,
    this.biometric = false,
    this.emailVerifier,
    this.wrappedKeyByEmail,
    this.emailRecovery = EmailRecovery.none,
  });

  final String id;
  final String displayName;
  final ProfileMode mode;
  final List<int> salt;
  final List<int> pinVerifier;
  final List<int> wrappedKeyByPin;
  final DateTime createdAt;
  final int failedAttempts;
  final DateTime? lockedUntil;
  final String? recoveryQuestion;
  final List<int>? recoveryVerifier;
  final List<int>? wrappedKeyByRecovery;

  /// E-mail address given at the creation (optional), for the account
  /// recovery by e-mail (Firebase Auth). Not health data.
  final String? email;

  /// Recovery by e-mail: master key wrapped by a random secret kept in
  /// Firestore, readable only once signed in to the Firebase account.
  final List<int>? emailVerifier;
  final List<int>? wrappedKeyByEmail;
  final EmailRecovery emailRecovery;

  /// Unlock with the fingerprint enabled (the key itself is kept apart).
  final bool biometric;

  bool get hasRecovery => recoveryQuestion != null && wrappedKeyByRecovery != null;
  bool get hasEmailRecovery => email != null && emailVerifier != null && wrappedKeyByEmail != null;

  ProfileInfo copyWith({
    String? displayName,
    ProfileMode? mode,
    List<int>? pinVerifier,
    List<int>? wrappedKeyByPin,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLock = false,
    bool? biometric,
    String? email,
    List<int>? emailVerifier,
    List<int>? wrappedKeyByEmail,
    EmailRecovery? emailRecovery,
    String? recoveryQuestion,
    List<int>? recoveryVerifier,
    List<int>? wrappedKeyByRecovery,
  }) => ProfileInfo(
    id: id,
    displayName: displayName ?? this.displayName,
    mode: mode ?? this.mode,
    salt: salt,
    pinVerifier: pinVerifier ?? this.pinVerifier,
    wrappedKeyByPin: wrappedKeyByPin ?? this.wrappedKeyByPin,
    createdAt: createdAt,
    failedAttempts: failedAttempts ?? this.failedAttempts,
    lockedUntil: clearLock ? null : (lockedUntil ?? this.lockedUntil),
    recoveryQuestion: recoveryQuestion ?? this.recoveryQuestion,
    recoveryVerifier: recoveryVerifier ?? this.recoveryVerifier,
    wrappedKeyByRecovery: wrappedKeyByRecovery ?? this.wrappedKeyByRecovery,
    email: email ?? this.email,
    biometric: biometric ?? this.biometric,
    emailVerifier: emailVerifier ?? this.emailVerifier,
    wrappedKeyByEmail: wrappedKeyByEmail ?? this.wrappedKeyByEmail,
    emailRecovery: emailRecovery ?? this.emailRecovery,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'display_name': displayName,
    'mode': mode.name,
    'salt': base64Encode(salt),
    'pin_verifier': base64Encode(pinVerifier),
    'wrapped_key_pin': base64Encode(wrappedKeyByPin),
    'created_at': createdAt.toUtc().toIso8601String(),
    'failed_attempts': failedAttempts,
    'locked_until': lockedUntil?.toUtc().toIso8601String(),
    'recovery_question': recoveryQuestion,
    'recovery_verifier': recoveryVerifier == null ? null : base64Encode(recoveryVerifier!),
    'wrapped_key_recovery': wrappedKeyByRecovery == null ? null : base64Encode(wrappedKeyByRecovery!),
    'email': email,
    'biometric': biometric,
    'email_verifier': emailVerifier == null ? null : base64Encode(emailVerifier!),
    'wrapped_key_email': wrappedKeyByEmail == null ? null : base64Encode(wrappedKeyByEmail!),
    'email_recovery': emailRecovery.name,
  };

  factory ProfileInfo.fromJson(Map<String, Object?> json) {
    List<int>? bytes(String key) {
      final value = json[key];
      return value is String ? base64Decode(value) : null;
    }

    final lockedUntil = json['locked_until'];
    return ProfileInfo(
      id: json['id']! as String,
      displayName: json['display_name']! as String,
      mode: ProfileMode.parse(json['mode']! as String),
      salt: bytes('salt')!,
      pinVerifier: bytes('pin_verifier')!,
      wrappedKeyByPin: bytes('wrapped_key_pin')!,
      createdAt: DateTime.parse(json['created_at']! as String),
      failedAttempts: (json['failed_attempts'] as int?) ?? 0,
      lockedUntil: lockedUntil is String ? DateTime.parse(lockedUntil) : null,
      recoveryQuestion: json['recovery_question'] as String?,
      recoveryVerifier: bytes('recovery_verifier'),
      wrappedKeyByRecovery: bytes('wrapped_key_recovery'),
      email: json['email'] as String?,
      biometric: json['biometric'] == true,
      emailVerifier: bytes('email_verifier'),
      wrappedKeyByEmail: bytes('wrapped_key_email'),
      emailRecovery: EmailRecovery.parse(json['email_recovery']),
    );
  }
}
