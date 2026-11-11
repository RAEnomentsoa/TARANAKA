import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';
import 'agent_labels.dart';
import 'agent_scope.dart';

/// Bottom sheet to choose the destination centre of a referral: centres of
/// [preferredType] first (those of the agent's region first), then the others.
Future<Centre?> pickCentre(BuildContext context, {String? preferredType}) async {
  final agent = AgentScope.read(context);
  final l10n = context.l10n;
  final all = await agent.repo.centres();
  if (!context.mounted) return null;
  return showModalBottomSheet<Centre>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final user = agent.account!.user;
      final type = preferredType;
      int rank(Centre c) => (c.type == type ? 0 : 2) + (c.regionId == user.regionId ? 0 : 1);
      final sorted = [...all]..sort((a, b) => rank(a).compareTo(rank(b)));
      final matching = type == null ? sorted : sorted.where((c) => c.type == type).toList();
      final others = type == null ? <Centre>[] : sorted.where((c) => c.type != type).toList();
      Widget tile(Centre c) => ListTile(
        key: ValueKey('centre-${c.id}'),
        leading: const Icon(Icons.local_hospital_outlined, color: AppColors.accent),
        title: Text(c.name),
        subtitle: Text('${centreTypeLabel(c.type)}${c.tel == null ? '' : ' · ${c.tel}'}'),
        onTap: () => Navigator.pop(context, c),
      );
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: Space.l),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: Text(l10n.chooseCentre, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: NoticeBox(icon: Icons.sync_problem, tone: Tone.warning, text: l10n.noCentre),
              ),
            ...matching.map(tile),
            if (others.isNotEmpty)
              ExpansionTile(title: Text(l10n.otherCentres), children: others.map(tile).toList()),
          ],
        ),
      );
    },
  );
}
