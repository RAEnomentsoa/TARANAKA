import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/personal_sync_controller.dart';
import 'cycle_sharing_tile.dart';
import 'my_code_screen.dart';
import 'region_field.dart';
import 'sync_state_pill.dart';

/// "Synchronisation" of the personal mode (D16): state (grey, orange,
/// green, red), what waits, the last sync, why it does not go through, and
/// "Synchroniser maintenant". Everything keeps working without network.
class PersonalSyncScreen extends StatelessWidget {
  const PersonalSyncScreen({super.key, required this.sync});

  final PersonalSyncController sync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final l10n = context.l10n;
        final report = sync.lastReport;
        final problem = switch (sync.problem) {
          PersonalSyncProblem.offline => l10n.syncProblemOffline,
          PersonalSyncProblem.noPin => l10n.syncProblemNoPin,
          PersonalSyncProblem.noRegion => l10n.syncProblemNoRegion,
          PersonalSyncProblem.regionUnknown => l10n.syncProblemRegion(sync.problemDetail ?? ''),
          PersonalSyncProblem.authExpired => l10n.syncProblemAuthPersonal,
          PersonalSyncProblem.server => l10n.syncProblemServer,
          null => null,
        };
        final account = sync.account;
        return AppScreen(
          title: l10n.agentSync,
          bottomAction: FilledButton.icon(
            key: const ValueKey('personal-sync-now'),
            onPressed: sync.syncing ? null : sync.syncNow,
            icon: sync.syncing
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: Text(sync.syncing ? l10n.syncRunning : l10n.syncNow),
          ),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SyncStatePill(sync, key: const ValueKey('personal-sync-state')),
                    const Gap(Space.m),
                    Text(
                      sync.lastSync == null ? l10n.syncNever : l10n.syncLast(formatDateTime(sync.lastSync!)),
                    ),
                    if (sync.pending > 0) ...[const Gap(Space.xs), Text(l10n.syncPendingCount(sync.pending))],
                    if (sync.failed > 0) ...[const Gap(Space.xs), Text(l10n.syncErrorsCount(sync.failed))],
                    if (sync.conflicts > 0) ...[
                      const Gap(Space.xs),
                      Text(l10n.syncConflictCount(sync.conflicts)),
                    ],
                    if (report != null && sync.problem == null && !sync.syncing) ...[
                      const Gap(Space.xs),
                      Text(l10n.syncDone(report.sent, report.received)),
                    ],
                  ],
                ),
              ),
            ),
            if (account == null) ...[
              const Gap(Space.m),
              NoticeBox(icon: Icons.cloud_off_outlined, tone: Tone.info, text: l10n.syncAccountPending),
            ],
            if (problem != null) ...[
              const Gap(Space.m),
              NoticeBox(
                key: const ValueKey('personal-sync-problem'),
                icon: sync.problem == PersonalSyncProblem.offline ? Icons.wifi_off : Icons.error_outline,
                tone: Tone.warning,
                text: problem,
              ),
            ],
            if (account == null &&
                (sync.problem == PersonalSyncProblem.noRegion ||
                    sync.problem == PersonalSyncProblem.regionUnknown ||
                    sync.registration?.region == null)) ...[
              const Gap(Space.m),
              RegionField(
                value: sync.registration?.region,
                onChanged: (r) {
                  if (r != null) sync.setRegion(r);
                },
              ),
            ],
            if (sync.conflicts > 0) ...[
              const Gap(Space.m),
              NoticeBox(icon: Icons.call_split, tone: Tone.danger, text: l10n.conflictExplain),
            ],
            const Gap(Space.l),
            Card(
              child: Column(
                children: [
                  ListTile(
                    key: const ValueKey('open-my-code'),
                    leading: const Icon(Icons.qr_code_2, color: AppColors.accent),
                    title: Text(l10n.myCodeTitle),
                    subtitle: Text(account == null ? l10n.myCodeNotYet : account.identifiant),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => MyCodeScreen(sync: sync))),
                  ),
                  const Divider(),
                  CycleSharingTile(sync: sync),
                ],
              ),
            ),
            if (sync.consentedAt != null) ...[
              const Gap(Space.l),
              Text(
                l10n.syncConsentDate(formatDate(sync.consentedAt!.toLocal())),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}
