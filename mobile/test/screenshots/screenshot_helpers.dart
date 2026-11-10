import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Screenshots for design review: `TARANAKA_SCREENSHOTS=1 flutter test test/screenshots`.
/// `TARANAKA_SCREENSHOTS=1 flutter test --update-goldens test/screenshots`
/// writes PNGs to test/screenshots/out/. Skipped otherwise.
final bool screenshotsEnabled = Platform.environment['TARANAKA_SCREENSHOTS'] == '1';

Future<void> loadRealFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final fonts = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');
  final roboto = FontLoader('Roboto');
  for (final f in fonts.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      roboto.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
    }
    if (name == 'MaterialIcons-Regular.otf') {
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await icons.load();
    }
  }
  await roboto.load();
}

Future<void> setPhone(WidgetTester tester, {double width = 360, double height = 760}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
}

/// Written with `--update-goldens` to test/screenshots/out/ (git-ignored).
Future<void> shot(WidgetTester tester, String name) async {
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
}
