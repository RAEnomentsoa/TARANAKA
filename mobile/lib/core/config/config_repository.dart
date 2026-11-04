import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'clinical_config.dart';

/// Loads the clinical configuration offline and keeps the newest valid one.
///
/// Order: the last version downloaded during a sync (a file in the app's
/// private folder), else the version bundled in the APK. The config is not
/// personal data, so it is shared by all profiles of the phone.
class ConfigRepository extends ChangeNotifier {
  ConfigRepository({required this.directory, AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const bundledAsset = 'assets/config/clinical_config_v1.json';
  static const fileName = 'clinical_config.json';

  final Future<Directory> Function() directory;
  final AssetBundle _bundle;

  ClinicalConfig? _current;

  ClinicalConfig get current {
    final config = _current;
    if (config == null) throw StateError('ConfigRepository.load() not called');
    return config;
  }

  bool get isLoaded => _current != null;

  Future<ClinicalConfig> load() async {
    final bundled = ClinicalConfig.fromJson(
      (jsonDecode(await _bundle.loadString(bundledAsset)) as Map).cast<String, Object?>(),
    );
    ClinicalConfig chosen = bundled;
    try {
      final file = File('${(await directory()).path}/$fileName');
      if (await file.exists()) {
        final json = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
        if (ClinicalConfig.problems(json).isEmpty) {
          final saved = ClinicalConfig.fromJson(json);
          if (saved.version >= bundled.version) chosen = saved;
        }
      }
    } on FormatException {
      // A damaged file is ignored: the bundled version still works offline.
    }
    _current = chosen;
    notifyListeners();
    return chosen;
  }

  /// Applies `config_clinique.mise_a_jour` from `/api/sync/pull/`.
  /// Returns true when a newer valid version was installed.
  Future<bool> applyUpdate(Map<String, Object?>? update) async {
    if (update == null) return false;
    if (ClinicalConfig.problems(update).isNotEmpty) return false;
    final config = ClinicalConfig.fromJson(update);
    if (_current != null && config.version <= _current!.version) return false;
    final dir = await directory();
    await dir.create(recursive: true);
    final tmp = File('${dir.path}/$fileName.tmp');
    await tmp.writeAsString(jsonEncode(config.toJson()), flush: true);
    await tmp.rename('${dir.path}/$fileName');
    _current = config;
    notifyListeners();
    return true;
  }
}
