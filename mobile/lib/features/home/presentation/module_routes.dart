import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';

/// Entry points of the modules, filled in step by step.
abstract final class ModuleRoutes {
  static Widget cycle() => const _NotYet();
  static Widget pregnancy() => const _NotYet();
  static Widget child() => const _NotYet();
  static Widget agentAccess() => const _NotYet();
  static Widget agentHome() => const _NotYet();
}

class _NotYet extends StatelessWidget {
  const _NotYet();

  @override
  Widget build(BuildContext context) => AppScreen(
        title: context.l10n.appName,
        children: [NoticeBox(icon: Icons.construction, text: context.l10n.comingNext)],
      );
}
