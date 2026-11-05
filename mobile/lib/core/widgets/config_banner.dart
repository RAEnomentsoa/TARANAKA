import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../i18n/l10n.dart';
import 'status_pill.dart';

/// Shown while the clinical configuration is not validated in writing
/// (spec §11, §15: sample config "À VALIDER").
class ConfigBanner extends StatelessWidget {
  const ConfigBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final config = AppScope.of(context).services.config.current;
    if (!config.toValidate) return const SizedBox.shrink();
    return NoticeBox(
      key: const ValueKey('config-banner'),
      icon: Icons.science_outlined,
      tone: Tone.caution,
      text: context.l10n.configToValidate(config.version),
    );
  }
}
