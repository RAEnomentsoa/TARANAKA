import 'package:flutter/services.dart';

/// A notification to show at [at] (local time).
class LocalReminder {
  const LocalReminder({required this.key, required this.at, required this.title, required this.body});

  /// Stable key (same reminder → same id, so it is replaced, not doubled).
  final String key;
  final DateTime at;
  final String title;
  final String body;

  int get id => stableId(key);
}

/// FNV-1a on the key, kept positive (an Android notification / alarm id).
int stableId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Local reminders, set by the phone itself (MainActivity "taranaka/reminders"):
/// no network. Without the native side (tests, other platforms) nothing
/// happens; the reminders still show in the app.
class LocalReminders {
  const LocalReminders._();

  static const _channel = MethodChannel('taranaka/reminders');

  /// Replaces the reminders of [group] (one group per profile and topic).
  static Future<void> schedule(
    String group,
    List<LocalReminder> reminders, {
    required String channelName,
    required String publicText,
  }) => _call('schedule', {
    'group': group,
    'channelName': channelName,
    'publicText': publicText,
    'items': [
      for (final r in reminders)
        {'id': r.id, 'at': r.at.millisecondsSinceEpoch, 'title': r.title, 'body': r.body},
    ],
  });

  static Future<void> cancelGroup(String group) => _call('cancelGroup', {'group': group});

  /// Asks once (Android 13+) to allow notifications.
  static Future<bool> requestPermission() async => await _call<bool>('requestNotifications') ?? false;

  static Future<bool> allowed() async => await _call<bool>('notificationsAllowed') ?? false;

  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
