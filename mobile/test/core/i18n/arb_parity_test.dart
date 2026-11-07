import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec §12: Malagasy, French and English at 100 %, no hard-coded text.
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

  test('every French text has a non-empty English text', () {
    final fr = read('fr');
    final en = read('en');
    final keys = fr.keys.where((k) => !k.startsWith('@'));
    for (final key in keys) {
      expect(en[key], isA<String>(), reason: 'missing en: $key');
      expect((en[key]! as String).trim(), isNotEmpty, reason: 'empty en: $key');
    }
    expect(en.keys.where((k) => !k.startsWith('@')).toSet(), keys.toSet());
  });

  test('placeholders are the same in every language', () {
    final fr = read('fr');
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final other in [read('mg'), read('en')]) {
      for (final key in fr.keys.where((k) => !k.startsWith('@'))) {
        Set<String> names(Object? s) => placeholder.allMatches(s! as String).map((m) => m.group(1)!).toSet();
        expect(names(other[key]), names(fr[key]), reason: key);
      }
    }
  });

  test('the month wheel has 12 names in every language', () {
    for (final lang in ['mg', 'fr', 'en']) {
      expect((read(lang)['monthNames']! as String).split('|'), hasLength(12), reason: lang);
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
        final literal = m.group(1)!;
        // Interpolated data (names, codes, dates) is not translatable text.
        final words = literal.replaceAll(RegExp(r'\$\{[^}]*\}?|\$\w+'), '');
        if (literal.startsWith(r'$') || !RegExp('[A-Za-zÀ-ÿ]{2,}').hasMatch(words)) continue;
        offenders.add('${file.path}: $literal');
      }
    }
    expect(offenders, isEmpty);
  });
}
