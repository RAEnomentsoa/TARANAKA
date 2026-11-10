import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/agent_controller.dart';
import 'agent_login_screen.dart';
import 'agent_scope.dart';

/// Sync state with icon and label (skill), "Synchroniser maintenant",
/// "Wi-Fi uniquement" (spec §9).
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final agent = AgentScope.of(context);
    final config = AppScope.of(context).services.config.current;
    final report = agent.lastReport;

    final (IconData icon, String status, Tone tone) = agent.syncing
        ? (Icons.sync, l10n.syncRunning, Tone.info)
        : agent.conflicts > 0
        ? (Icons.call_split, l10n.syncConflictCount(agent.conflicts), Tone.danger)
        : agent.pending > 0
        ? (Icons.cloud_upload_outlined, l10n.syncPendingCount(agent.pending), Tone.warning)
        : (Icons.cloud_done_outlined, l10n.syncSynced, Tone.success);

    final problem = switch (agent.problem) {
      SyncProblem.offline => l10n.syncProblemOffline,
      SyncProblem.wifiOnly => l10n.syncProblemWifi,
      SyncProblem.authExpired => l10n.syncProblemAuth,
      SyncProblem.server => l10n.syncProblemServer,
      SyncProblem.notLoggedIn => l10n.syncProblemAuth,
      null => null,
    };

    return AppScreen(
      title: l10n.agentSync,
      bottomAction: FilledButton.icon(
        key: const ValueKey('sync-now'),
        onPressed: agent.syncing ? null : () => agent.syncNow(manual: true, language: context.lang),
        icon: agent.syncing
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sync),
        label: Text(agent.syncing ? l10n.syncRunning : l10n.syncNow),
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(icon: icon, label: status, tone: tone),
                const Gap(Space.m),
                Text(
                  agent.lastSync == null ? l10n.syncNever : l10n.syncLast(formatDateTime(agent.lastSync!)),
                ),
                if (agent.pending > 0 && agent.conflicts > 0) ...[
                  const Gap(Space.xs),
                  Text(l10n.syncPendingCount(agent.pending)),
                ],
                if (report != null && agent.problem == null && !agent.syncing) ...[
                  const Gap(Space.xs),
                  Text(l10n.syncDone(report.sent, report.received)),
                  if (report.failed > 0) Text(l10n.syncErrorsCount(report.failed)),
                ],
              ],
            ),
          ),
        ),
        if (problem != null) ...[
          const Gap(Space.m),
          NoticeBox(
            key: const ValueKey('sync-problem'),
            icon: agent.problem == SyncProblem.offline ? Icons.wifi_off : Icons.error_outline,
            tone: Tone.warning,
            text: problem,
          ),
        ],
        if (agent.problem == SyncProblem.authExpired) ...[
          const Gap(Space.s),
          OutlinedButton.icon(
            onPressed: () => pushAgent<void>(context, const AgentLoginScreen()),
            icon: const Icon(Icons.login),
            label: Text(l10n.reconnect),
          ),
        ],
        if (agent.conflicts > 0) ...[
          const Gap(Space.m),
          NoticeBox(icon: Icons.call_split, tone: Tone.danger, text: l10n.conflictExplain),
        ],
        const Gap(Space.l),
        Card(
          child: SwitchListTile(
            key: const ValueKey('wifi-only'),
            secondary: const Icon(Icons.wifi),
            title: Text(l10n.syncWifiOnly),
            subtitle: Text(l10n.syncWifiOnlyHint),
            value: agent.wifiOnly,
            onChanged: agent.setWifiOnly,
          ),
        ),
        const Gap(Space.l),
        Text(l10n.agentAccount(agent.account?.user.displayName ?? '')),
        Text(agent.account?.baseUrl ?? '', style: Theme.of(context).textTheme.bodySmall),
        Text(l10n.aboutConfig(config.version), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
