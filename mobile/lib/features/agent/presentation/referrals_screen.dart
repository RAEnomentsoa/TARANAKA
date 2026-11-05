import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/states.dart';
import '../domain/models.dart';
import 'agent_labels.dart';
import 'agent_scope.dart';
import 'referral_sheet_screen.dart';

class ReferralsScreen extends StatelessWidget {
  const ReferralsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final agent = AgentScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.agentReferrals)),
      body: SafeArea(
        child: FutureBuilder<List<(Referral, Child?)>>(
          future: () async {
            final list = await agent.repo.referrals();
            return [for (final r in list) (r, r.childId == null ? null : await agent.repo.child(r.childId!))];
          }(),
          builder: (context, snap) {
            if (snap.hasError) return const ErrorView();
            if (!snap.hasData) return const LoadingView();
            final items = snap.data!;
            if (items.isEmpty) {
              return EmptyView(icon: Icons.assignment_outlined, message: l10n.noReferrals);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(Space.l),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.s),
              itemBuilder: (context, i) {
                final (r, child) = items[i];
                return Card(
                  child: InkWell(
                    key: ValueKey('referral-${r.id}'),
                    borderRadius: BorderRadius.circular(Radii.l),
                    onTap: () => pushAgent<void>(context, ReferralSheetScreen(referralId: r.id)),
                    child: Padding(
                      padding: const EdgeInsets.all(Space.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.code,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 1),
                          ),
                          Text('${child?.name ?? ''} · ${formatDateTime(r.referredAt)}'),
                          const SizedBox(height: Space.s),
                          Wrap(
                            spacing: Space.s,
                            runSpacing: Space.s,
                            children: [UrgencyPill(r.urgence), ReferralStatusPill(r)],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
