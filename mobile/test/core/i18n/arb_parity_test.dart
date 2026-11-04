import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec §12: French and Malagasy at 100 %, no hard-coded text.
void main() {
  Map<String, Object?> read(String lang) =>
      (jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map).cast();

  test('every French text has a non-empty Malagasy text', () {
    final fr = read('fr');
    final mg = read('mg');
    final keys = fr.keys.where((k) => !k.startsWith('@'));
    for (final key in keys) {
      expect(mg[key], isA<String>(), reason: 'missing mg: $key');
      expect((mg[key]! as String).trim(), isNotEmpty, reason: 'empty mg: $key');
    }
    expect(mg.keys.where((k) => !k.startsWith('@')).toSet(), keys.toSet());
  });

  test('placeholders are the same in both languages', () {
    final fr = read('fr');
    final mg = read('mg');
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final key in fr.keys.where((k) => !k.startsWith('@'))) {
      Set<String> names(Object? s) =>
          placeholder.allMatches(s! as String).map((m) => m.group(1)!).toSet();
      expect(names(mg[key]), names(fr[key]), reason: key);
    }
  });

  test('no user-visible French string literal in widgets', () {
    // Heuristic: Text('...') with a letter inside, outside the language screen
    // (which shows both language names on purpose).
    final offenders = <String>[];
    for (final file in Directory('lib/features').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart') || file.path.endsWith('language_screen.dart')) continue;
      final src = file.readAsStringSync();
      for (final m in RegExp(r"""Text\(\s*'([^']*[A-Za-zÀ-ÿ][^']*)'""").allMatches(src)) {
        offenders.add('${file.path}: ${m.group(1)}');
      }
    }
    expect(offenders, isEmpty);
  });
}
