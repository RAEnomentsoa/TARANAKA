import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/personal_sync_controller.dart';

/// Grey, orange, green, red — always with an icon and a label (spec §9).
class SyncStatePill extends StatelessWidget {
  const SyncStatePill(this.sync, {super.key});
  final PersonalSyncController sync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (sync.syncing) return StatusPill(icon: Icons.sync, label: l10n.syncRunning, tone: Tone.info);
    return switch (sync.state) {
      PersonalSyncState.local => StatusPill(
        icon: Icons.phone_android,
        label: l10n.syncStateLocal,
        tone: Tone.neutral,
      ),
      PersonalSyncState.pending => StatusPill(
        icon: Icons.cloud_upload_outlined,
        label: l10n.syncPendingCount(sync.pending),
        tone: Tone.warning,
      ),
      PersonalSyncState.synced => StatusPill(
        icon: Icons.cloud_done_outlined,
        label: l10n.syncSynced,
        tone: Tone.success,
      ),
      PersonalSyncState.error => StatusPill(
        icon: Icons.sync_problem,
        label: l10n.syncStateError,
        tone: Tone.danger,
      ),
    };
  }
}
