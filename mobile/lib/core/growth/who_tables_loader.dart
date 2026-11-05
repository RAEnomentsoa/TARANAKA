import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'who_lms.dart';

/// Loads the WHO tables bundled in assets/who/. Missing files are simply
/// absent: the matching z-scores stay empty (never invented).
abstract final class WhoTablesLoader {
  static Future<WhoTables> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    final contents = <WhoIndicator, String>{};
    for (final i in WhoIndicator.values) {
      try {
        contents[i] = await assets.loadString('assets/who/${i.fileName}', cache: false);
      } on FlutterError {
        // Not bundled.
      }
    }
    return WhoTables.fromFiles(contents);
  }

  /// The files to add, for the message shown when they are missing.
  static List<String> missingFiles(WhoTables tables) => [
    for (final i in WhoIndicator.values)
      if (!tables.has(i)) i.fileName,
  ];
}
