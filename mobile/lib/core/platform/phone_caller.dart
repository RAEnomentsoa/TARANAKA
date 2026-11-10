import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum CallOutcome {
  /// The call started (CALL_PHONE allowed).
  called,

  /// The dialer opened with the number: one more tap to call.
  dialer,
  failed,
}

/// Calls through the phone network (no Internet needed), see MainActivity
/// "taranaka/phone". Without the native side (tests, other platforms): the
/// `tel:` link.
class PhoneCaller {
  const PhoneCaller._();

  static const _channel = MethodChannel('taranaka/phone');

  /// Keeps what a dialer understands: digits, "+", "*" and "#".
  static String clean(String number) => number.replaceAll(RegExp(r'[^0-9+*#]'), '');

  static Future<CallOutcome> call(String number) async {
    final n = clean(number);
    if (n.isEmpty) return CallOutcome.failed;
    try {
      final r = await _channel.invokeMethod<String>('call', {'number': n});
      return CallOutcome.values.firstWhere((o) => o.name == r, orElse: () => CallOutcome.failed);
    } on MissingPluginException {
      return await _launch(Uri(scheme: 'tel', path: n)) ? CallOutcome.dialer : CallOutcome.failed;
    } on PlatformException {
      return await _launch(Uri(scheme: 'tel', path: n)) ? CallOutcome.dialer : CallOutcome.failed;
    }
  }

  /// Asks once (system dialog) to call in one tap from the red alert.
  static Future<bool> requestDirectCalls() async {
    try {
      return await _channel.invokeMethod<bool>('requestCallPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens a map app on [query] ("Ouvrir l'itinéraire"): offline map apps
  /// work too; online ones need the network.
  static Future<bool> openMap(String query) => _launch(Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}'));

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}
