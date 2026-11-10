import 'dart:convert';
import 'dart:io';

import 'package:taranaka/core/config/clinical_config.dart';

/// The bundled sample configuration ("À VALIDER"), read from the asset file.
ClinicalConfig sampleConfig() => ClinicalConfig.fromJson(
  (jsonDecode(File('assets/config/clinical_config_v1.json').readAsStringSync()) as Map)
      .cast<String, Object?>(),
);
