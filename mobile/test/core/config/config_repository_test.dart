import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/config/clinical_config.dart';
import 'package:taranaka/core/config/config_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ConfigRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('taranaka_cfg');
    repo = ConfigRepository(directory: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Map<String, Object?>> bundled() async =>
      (jsonDecode(await rootBundle.loadString(ConfigRepository.bundledAsset)) as Map)
          .cast<String, Object?>();

  test('offline: the bundled sample loads, marked À VALIDER', () async {
    final config = await repo.load();
    expect(config.version, 1);
    expect(config.toValidate, isTrue);
    expect(config.meta['statut_validation'], 'À VALIDER');
    expect(config.malnutrition['age_max_mois'], 59);
  });

  test('the bundled file is the backend sample, unchanged', () async {
    final backend = jsonDecode(
      File('../Backend_serveur/config_clinique/exemples/config_clinique_exemple.json')
          .readAsStringSync(),
    );
    expect((await bundled())['contenu'], backend);
  });

  test('every section and every rule of the sample says À VALIDER', () async {
    final contenu = ((await bundled())['contenu']! as Map).cast<String, Object?>();
    for (final entry in contenu.entries.where((e) => e.key != 'meta')) {
      expect((entry.value! as Map)['statut'], 'À VALIDER', reason: entry.key);
    }
    final mal = contenu['malnutrition']! as Map;
    for (final rule in [
      ...((mal['classification'] as Map)['regles'] as List),
      ...((mal['orientation'] as Map)['regles'] as List),
    ]) {
      expect((rule as Map)['statut'], 'À VALIDER');
    }
  });

  test('a newer version from the server replaces it and is kept offline', () async {
    await repo.load();
    final update = await bundled();
    update['version'] = 2;
    update['statut_validation'] = 'validee';
    expect(await repo.applyUpdate(update), isTrue);
    expect(repo.current.version, 2);

    final reloaded = ConfigRepository(directory: () async => dir);
    expect((await reloaded.load()).version, 2);
  });

  test('older, same or broken versions are refused', () async {
    await repo.load();
    final same = await bundled();
    expect(await repo.applyUpdate(same), isFalse);
    final broken = await bundled();
    broken['version'] = 3;
    (broken['contenu']! as Map).remove('signes_danger');
    expect(ClinicalConfig.problems(broken), contains('signes_danger'));
    expect(await repo.applyUpdate(broken), isFalse);
    expect(await repo.applyUpdate(null), isFalse);
    expect(repo.current.version, 1);
  });

  test('a damaged saved file falls back to the bundled version', () async {
    File('${dir.path}/${ConfigRepository.fileName}').writeAsStringSync('{not json');
    expect((await repo.load()).version, 1);
  });

  test('localized texts fall back to French while Malagasy is missing', () {
    expect(localizedText({'fr': 'Fièvre', 'mg': null}, 'mg'), 'Fièvre');
    expect(localizedText({'fr': 'Fièvre', 'mg': 'Tazo'}, 'mg'), 'Tazo');
    expect(localizedText('vary', 'fr'), 'vary');
    expect(localizedText(null, 'fr'), '');
  });
}
