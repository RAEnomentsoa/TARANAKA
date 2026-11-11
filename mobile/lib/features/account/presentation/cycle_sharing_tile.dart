import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/widgets/states.dart';
import '../data/personal_sync_controller.dart';

/// "Partager mon cycle" (D16 option a): off by default, the cycle and the
/// daily follow-up stay on the phone. Each change is confirmed: on, they are
/// sent and seen by the health staff who follow her; off, the server erases
/// its copy.
class CycleSharingTile extends StatelessWidget {
  const CycleSharingTile({super.key, required this.sync});

  final PersonalSyncController sync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) => SwitchListTile(
        key: const ValueKey('share-cycle'),
        secondary: const Icon(Icons.water_drop_outlined),
        title: Text(l10n.cycleShareTitle),
        subtitle: Text(l10n.cycleShareHint),
        value: sync.cycleShared,
        onChanged: (share) async {
          final ok = await confirmAction(
            context,
            message: share ? l10n.cycleShareOnConfirm : l10n.cycleShareOffConfirm,
            confirmLabel: share ? l10n.cycleShareOn : l10n.cycleShareOff,
          );
          if (ok) await sync.setCycleSharing(share);
        },
      ),
    );
  }
}
