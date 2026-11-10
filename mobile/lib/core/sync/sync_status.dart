import 'package:flutter/material.dart';

import '../i18n/l10n.dart';
import '../widgets/status_pill.dart';

/// Status shown on every record (spec §9).
enum SyncStatus {
  /// Enregistré (grey): on the phone only.
  saved,

  /// À synchroniser (orange): waiting in the outbox.
  pending,

  /// Synchronisé (green): acknowledged by the server.
  synced,

  /// Conflit (red): the server kept both versions for a person to decide.
  conflict;

  static SyncStatus parse(Object? v) =>
      SyncStatus.values.firstWhere((s) => s.name == v, orElse: () => SyncStatus.saved);
}

class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill(this.status, {super.key});
  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (status) {
      SyncStatus.saved => StatusPill(icon: Icons.phone_android, label: l10n.syncSaved, tone: Tone.neutral),
      SyncStatus.pending => StatusPill(
        icon: Icons.cloud_upload_outlined,
        label: l10n.syncPending,
        tone: Tone.warning,
      ),
      SyncStatus.synced => StatusPill(
        icon: Icons.cloud_done_outlined,
        label: l10n.syncSynced,
        tone: Tone.success,
      ),
      SyncStatus.conflict => StatusPill(icon: Icons.call_split, label: l10n.syncConflict, tone: Tone.danger),
    };
  }
}
