import 'dart:convert';

enum ProfileMode {
  /// "Pour moi et ma famille": no account, local PIN only.
  personal,

  /// "Je suis agent de santé": named server account + local PIN.
  agent;

  static ProfileMode parse(String value) =>
      ProfileMode.values.firstWhere((m) => m.name == value, orElse: () => ProfileMode.personal);
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

  bool get hasRecovery => recoveryQuestion != null && wrappedKeyByRecovery != null;

  ProfileInfo copyWith({
    String? displayName,
    ProfileMode? mode,
    List<int>? pinVerifier,
    List<int>? wrappedKeyByPin,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLock = false,
  }) =>
      ProfileInfo(
        id: id,
        displayName: displayName ?? this.displayName,
        mode: mode ?? this.mode,
        salt: salt,
        pinVerifier: pinVerifier ?? this.pinVerifier,
        wrappedKeyByPin: wrappedKeyByPin ?? this.wrappedKeyByPin,
        createdAt: createdAt,
        failedAttempts: failedAttempts ?? this.failedAttempts,
        lockedUntil: clearLock ? null : (lockedUntil ?? this.lockedUntil),
        recoveryQuestion: recoveryQuestion,
        recoveryVerifier: recoveryVerifier,
        wrappedKeyByRecovery: wrappedKeyByRecovery,
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
        'wrapped_key_recovery':
            wrappedKeyByRecovery == null ? null : base64Encode(wrappedKeyByRecovery!),
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
    );
  }
}
