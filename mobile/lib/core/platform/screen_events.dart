import 'package:flutter/services.dart';

/// The phone screen turning off, sent by the Android side (`MainActivity`)
/// on the `taranaka/screen` channel. On a platform without it (tests, other
/// systems), nothing is ever reported and nothing fails.
class ScreenEvents {
  ScreenEvents._();

  static const channel = MethodChannel('taranaka/screen');

  /// Calls [onScreenOff] each time the screen turns off, while the app runs.
  static void listen(Future<void> Function() onScreenOff) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'screenOff') await onScreenOff();
      return null;
    });
  }

  static void stop() => channel.setMethodCallHandler(null);

  /// True when the screen turned off since the last call (a lock that could
  /// not be applied at once, e.g. while the app was in the background).
  static Future<bool> takeScreenOff() async {
    try {
      return await channel.invokeMethod<bool>('takeScreenOff') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
