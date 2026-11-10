import 'package:flutter/services.dart';

/// Saves a small text file where the user chooses (system "Save as" dialog,
/// Android `MainActivity`, channel `taranaka/files`): Downloads, Drive, a
/// memory card… No storage permission is needed.
class TextFileSaver {
  TextFileSaver._();

  static const channel = MethodChannel('taranaka/files');

  /// True when the file was written; false when cancelled or unavailable.
  static Future<bool> save({required String fileName, required String text}) async {
    try {
      return await channel.invokeMethod<bool>('saveText', {'name': fileName, 'text': text}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
