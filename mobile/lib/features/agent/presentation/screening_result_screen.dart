import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/growth/who_tables_loader.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';
import '../domain/screening.dart';
import 'agent_labels.dart';
import 'agent_scope.dart';
import 'referral_sheet_screen.dart';

/// Classification and orientation, computed offline from the configuration.
class ScreeningResultScreen extends StatefulWidget {
  const ScreeningResultScreen({
    super.key,
    required this.child,
    required this.input,
    required this.result,
    required this.measurement,
  });

  final Child child;
  final ScreeningInput input;
  final ScreeningResult result;
  final Measurement measurement;

  @override
  State<ScreeningResultScreen> createState() => _ScreeningResultScreenState();
}

class _ScreeningResultScreenState extends State<ScreeningResultScreen> {
  bool _busy = false;

  Future<void> _refer() async {
    final agent = AgentScope.read(context);
    final l10n = context.l10n;
    final all = await agent.repo.centres();
    if (!mounted) return;
    final centre = await showModalBottomSheet<Centre>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final user = agent.account!.user;
        final type = widget.result.centre;
        int rank(Centre c) => (c.type == type ? 0 : 2) + (c.regionId == user.regionId ? 0 : 1);
        final sorted = [...all]..sort((a, b) => rank(a).compareTo(rank(b)));
        final matching = sorted.where((c) => c.type == type).toList();
        final others = sorted.where((c) => c.type != type).toList();
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
    if (centre == null || !mounted) return;
    setState(() => _busy = true);
    final referral = await agent.repo.createReferral(
      child: widget.child,
      measurement: widget.measurement,
      result: widget.result,
      centre: centre,
      motif: ScreeningCalculator.motif(widget.input, widget.result),
      agentId: agent.account!.user.id,
    );
    await agent.refreshCounts();
    if (!mounted) return;
    await pushAgent<void>(context, ReferralSheetScreen(referralId: referral.id), replace: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = widget.result;
    final config = AppScope.of(context).services.config.current;
    final agent = AgentScope.of(context);
    final missing = WhoTablesLoader.missingFiles(agent.tables);
    final advice = asMapList(config.alimentationEnfant['conseils'])
        .where((c) => c['code'] == r.adviceCode)
        .firstOrNull;
    final text = Theme.of(context).textTheme;

    return AppScreen(
      title: l10n.resultTitle,
      bottomAction: r.needsReferral
          ? FilledButton.icon(
              key: const ValueKey('create-referral'),
              onPressed: _busy ? null : _refer,
              icon: const Icon(Icons.assignment_outlined),
              label: Text(l10n.createReferral),
            )
          : FilledButton(
              key: const ValueKey('result-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.done),
            ),
      children: [
        NoticeBox(icon: Icons.check_circle_outline, tone: Tone.success, text: l10n.measureSaved),
        const Gap(Space.l),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.child.name, style: text.titleLarge),
                Text(l10n.ageMonths(r.ageMonths)),
                const Gap(Space.m),
                Transform.scale(
                  scale: 1.15,
                  alignment: Alignment.centerLeft,
                  child: ClassificationPill(r.classification),
                ),
                const Gap(Space.m),
                if (r.needsReferral) ...[
                  Text(l10n.orientationTo(centreTypeLabel(r.centre)), style: text.titleMedium),
                  const Gap(Space.s),
                  UrgencyPill(r.urgence),
                ] else
                  Text(l10n.noReferralNeeded, style: text.bodyLarge),
                if (r.nextCheck != null) ...[
                  const Gap(Space.m),
                  Row(
                    children: [
                      const Icon(Icons.event_outlined, color: AppColors.accent),
                      const SizedBox(width: Space.s),
                      Expanded(child: Text(l10n.nextCheck(formatDate(r.nextCheck!)))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        SectionTitle(l10n.referralMeasures),
        Text(
          [
            '${formatDecimal(widget.input.weightKg)} kg',
            '${formatDecimal(widget.input.lengthCm)} cm',
            if (widget.input.muacMm != null) 'PB ${widget.input.muacMm} mm',
            if (widget.input.oedema != 'aucun') '${l10n.oedema} ${widget.input.oedema}',
          ].join(' · '),
        ),
        SectionTitle(l10n.zscoresTitle),
        if (r.zscores.any)
          Text(
            [
              if (r.zscores.whz != null) '${l10n.zWfh} ${formatDecimal(r.zscores.whz!, digits: 2)}',
              if (r.zscores.waz != null) '${l10n.zWfa} ${formatDecimal(r.zscores.waz!, digits: 2)}',
              if (r.zscores.haz != null) '${l10n.zHfa} ${formatDecimal(r.zscores.haz!, digits: 2)}',
            ].join(' · '),
          )
        else
          NoticeBox(
            icon: Icons.table_chart_outlined,
            tone: Tone.caution,
            text: l10n.zscoresMissing(missing.join(', ')),
          ),
        if (advice != null) ...[
          SectionTitle(l10n.adviceSource(config.sourceLabel('alimentation_enfant'))),
          NoticeBox(icon: Icons.lightbulb_outline, text: localizedText(advice, context.lang)),
        ],
        const Gap(Space.l),
        Text(l10n.alertDisclaimer, style: text.bodySmall),
      ],
    );
  }
}
