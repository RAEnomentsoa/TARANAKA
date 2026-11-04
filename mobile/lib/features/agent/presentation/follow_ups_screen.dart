import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';
import 'agent_child_screen.dart';
import 'agent_labels.dart';
import 'agent_scope.dart';
import 'referral_sheet_screen.dart';

/// What the agent should chase (spec §7, §10): referrals not arrived after the
/// configured delay, children due for a check, missed appointments.
class FollowUpsScreen extends StatelessWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final agent = AgentScope.of(context);
    final config = AppScope.of(context).services.config.current;
    final delay = asInt((config.malnutrition['suivi'] as Map?)?['delai_alerte_non_arrivee_heures']);

    return FutureBuilder<(List<(Referral, Child?)>, List<(Child, Measurement)>, List<(Appointment, Child?)>)>(
      future: () async {
        final late = await agent.repo.notArrived(delayHours: delay);
        final due = await agent.repo.childrenDue();
        final missed = await agent.repo.missedAppointments();
        return (
          [for (final r in late) (r, r.childId == null ? null : await agent.repo.child(r.childId!))],
          due,
          [for (final a in missed) (a, a.childId == null ? null : await agent.repo.child(a.childId!))],
        );
      }(),
      builder: (context, snap) {
        if (snap.hasError) return const Scaffold(body: ErrorView());
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (late, due, missed) = snap.data!;
        final empty = late.isEmpty && due.isEmpty && missed.isEmpty;
        return AppScreen(
          title: l10n.agentFollowUps,
          children: [
            if (empty) EmptyView(icon: Icons.event_available, message: l10n.followNone),
            if (late.isNotEmpty) ...[
              SectionTitle(l10n.followNotArrived(delay ?? 0)),
              for (final (r, child) in late)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.directions_walk, color: AppColors.warning),
                    title: Text(child?.name ?? r.code),
                    subtitle: Text('${r.code} · ${formatDateTime(r.referredAt)}'),
                    trailing: UrgencyPill(r.urgence),
                    onTap: () => pushAgent<void>(context, ReferralSheetScreen(referralId: r.id)),
                  ),
                ),
            ],
            if (due.isNotEmpty) ...[
              SectionTitle(l10n.followDue),
              for (final (child, m) in due)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_repeat, color: AppColors.accent),
                    title: Text(child.name),
                    subtitle: Text(l10n.nextCheck(formatDate(m.nextCheck!))),
                    trailing: ClassificationPill(m.classification),
                    onTap: () => pushAgent<void>(context, AgentChildScreen(childId: child.id)),
                  ),
                ),
            ],
            if (missed.isNotEmpty) ...[
              SectionTitle(l10n.followMissed),
              for (final (a, child) in missed)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_busy, color: AppColors.danger),
                    title: Text(child?.name ?? ''),
                    subtitle: Text('${formatDate(a.date)}${a.reason == null ? '' : ' · ${a.reason}'}'),
                    trailing: StatusPill(icon: Icons.event_busy, label: l10n.followMissed, tone: Tone.danger),
                    onTap: child == null
                        ? null
                        : () => pushAgent<void>(context, AgentChildScreen(childId: child.id)),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
