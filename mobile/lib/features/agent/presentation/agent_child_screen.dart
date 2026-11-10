import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';
import '../domain/screening.dart';
import 'agent_labels.dart';
import 'agent_scope.dart';
import 'measurement_form_screen.dart';
import 'referral_sheet_screen.dart';

/// A child followed by the agent: successive measurements and referrals.
class AgentChildScreen extends StatefulWidget {
  const AgentChildScreen({super.key, required this.childId});
  final String childId;

  @override
  State<AgentChildScreen> createState() => _AgentChildScreenState();
}

class _AgentChildScreenState extends State<AgentChildScreen> {
  Future<(Child?, List<Measurement>, List<Referral>)>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(Child?, List<Measurement>, List<Referral>)> _load() async {
    final repo = AgentScope.read(context).repo;
    return (
      await repo.child(widget.childId),
      await repo.measurements(widget.childId),
      await repo.referrals(childId: widget.childId),
    );
  }

  /// Reloads unless the screen was closed meanwhile (e.g. the app locked
  /// itself and closed the database).
  void _reload() {
    if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
    setState(() {
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<(Child?, List<Measurement>, List<Referral>)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (child, measures, referrals) = snap.data!;
        if (child == null) return const Scaffold(body: ErrorView());
        final months = ScreeningCalculator.ageMonths(
          ScreeningCalculator.ageDays(child.birthDate, DateTime.now()),
        );
        return AppScreen(
          title: child.name,
          bottomAction: FilledButton.icon(
            key: const ValueKey('new-measure'),
            onPressed: () =>
                pushAgent<void>(context, MeasurementFormScreen(childId: child.id)).then((_) => _reload()),
            icon: const Icon(Icons.straighten),
            label: Text(l10n.agentScreen),
          ),
          children: [
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                StatusPill(
                  icon: child.sex == 'F' ? Icons.girl : Icons.boy,
                  label: '${child.sex == 'F' ? l10n.sexF : l10n.sexM} · ${l10n.ageMonths(months)}',
                  tone: Tone.info,
                ),
                StatusPill(icon: Icons.cake_outlined, label: formatDate(child.birthDate), tone: Tone.neutral),
                SyncStatusPill(child.syncStatus),
              ],
            ),
            if (child.syncStatus == SyncStatus.conflict) ...[
              const Gap(Space.m),
              NoticeBox(icon: Icons.call_split, tone: Tone.danger, text: l10n.conflictExplain),
            ],
            if (referrals.isNotEmpty) SectionTitle(l10n.agentReferrals),
            for (final r in referrals)
              Card(
                child: ListTile(
                  title: Text(r.code, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: ReferralStatusPill(r),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => pushAgent<void>(context, ReferralSheetScreen(referralId: r.id)),
                ),
              ),
            SectionTitle(l10n.childHistory),
            if (measures.isEmpty) EmptyView(icon: Icons.straighten, message: l10n.followNone),
            for (final m in measures) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatDate(m.date), style: Theme.of(context).textTheme.titleSmall),
                      const Gap(Space.xs),
                      Text(
                        [
                          '${formatDecimal(m.weightKg)} kg',
                          '${formatDecimal(m.lengthCm)} cm',
                          if (m.muacMm != null) 'PB ${m.muacMm} mm',
                          if (m.whz != null) 'P/T ${formatDecimal(m.whz!, digits: 2)} z',
                        ].join(' · '),
                      ),
                      const Gap(Space.s),
                      Wrap(
                        spacing: Space.s,
                        runSpacing: Space.s,
                        children: [ClassificationPill(m.classification), SyncStatusPill(m.syncStatus)],
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(Space.s),
            ],
          ],
        );
      },
    );
  }
}
