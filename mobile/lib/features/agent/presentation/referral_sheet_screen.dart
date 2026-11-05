import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Full-screen referral form to show the nurse (spec §7), offline.
class ReferralSheetScreen extends StatelessWidget {
  const ReferralSheetScreen({super.key, required this.referralId});
  final String referralId;

  Future<(Referral, Child?, Measurement?, Centre?)?> _load(BuildContext context) async {
    final repo = AgentScope.read(context).repo;
    final r = await repo.referral(referralId);
    if (r == null) return null;
    return (
      r,
      r.childId == null ? null : await repo.child(r.childId!),
      r.measurementId == null ? null : await repo.measurement(r.measurementId!),
      await repo.centre(r.centreId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final agent = AgentScope.of(context);
    return FutureBuilder<(Referral, Child?, Measurement?, Centre?)?>(
      // Rebuilt when the sync changes something (AgentScope.of listens).
      future: _load(context),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: LoadingView());
        }
        final data = snap.data;
        if (data == null) return const Scaffold(body: ErrorView());
        final (r, child, m, centre) = data;
        final text = Theme.of(context).textTheme;
        final user = agent.account?.user;
        final months = child == null || m == null
            ? null
            : ScreeningCalculator.ageMonths(ScreeningCalculator.ageDays(child.birthDate, m.date));
        final measures = m == null
            ? ''
            : [
                '${formatDecimal(m.weightKg)} kg',
                '${formatDecimal(m.lengthCm)} cm',
                if (m.muacMm != null) 'PB ${m.muacMm} mm',
                if (m.oedema != 'aucun') '${l10n.oedema} ${m.oedema}',
                if (m.whz != null) 'P/T ${formatDecimal(m.whz!, digits: 2)} z',
              ].join(' · ');
        final summary = [
          '${l10n.referralTitle} ${r.code}',
          if (child != null)
            '${l10n.referralChild}: ${child.name}, ${child.sex == 'F' ? l10n.sexF : l10n.sexM}, ${formatDate(child.birthDate)}${months == null ? '' : ' (${l10n.ageMonths(months)})'}',
          if (m != null) '${l10n.referralMeasures}: $measures',
          '${classificationLabel(context, m?.classification)} – ${r.urgence ?? ''}',
          '${l10n.referralReason}: ${r.motif}',
          if (centre != null) '${l10n.referralDestination}: ${centre.name} (${centreTypeLabel(centre.type)})',
          if (user != null) '${l10n.referralAgent}: ${user.displayName}',
          '${l10n.referralDate}: ${formatDateTime(r.referredAt)}',
        ].join('\n');

        Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.accent),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
                    Text(value, style: text.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
        );

        return AppScreen(
          title: l10n.referralTitle,
          bottomAction: OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: summary));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.copied)));
              }
            },
            icon: const Icon(Icons.copy),
            label: Text(l10n.copyReferral),
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(Space.l),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(Radii.l),
                border: Border.all(color: AppColors.accentSoftBorder),
              ),
              child: Column(
                children: [
                  Text(l10n.referralCode, style: text.labelLarge),
                  const Gap(Space.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SelectableText(
                      r.code,
                      key: const ValueKey('referral-code'),
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const Gap(Space.m),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      ReferralStatusPill(r),
                      UrgencyPill(r.urgence),
                      if (r.syncStatus == SyncStatus.conflict) SyncStatusPill(r.syncStatus),
                    ],
                  ),
                ],
              ),
            ),
            if (r.previousCode != null) ...[
              const Gap(Space.m),
              NoticeBox(
                icon: Icons.info_outline,
                tone: Tone.caution,
                text: l10n.referralOldCode(r.previousCode!),
              ),
            ],
            const Gap(Space.m),
            if (child != null)
              row(
                child.sex == 'F' ? Icons.girl : Icons.boy,
                l10n.referralChild,
                '${child.name} · ${child.sex == 'F' ? l10n.sexF : l10n.sexM} · ${formatDate(child.birthDate)}${months == null ? '' : ' · ${l10n.ageMonths(months)}'}',
              ),
            if (m != null) row(Icons.straighten, l10n.referralMeasures, measures),
            row(Icons.assignment_late_outlined, l10n.referralReason, r.motif),
            if (m != null && m.dangerSigns.isNotEmpty)
              row(Icons.warning_amber, l10n.dangerSigns, m.dangerSigns.join(', ')),
            if (centre != null)
              row(
                Icons.local_hospital_outlined,
                l10n.referralDestination,
                '${centre.name} (${centreTypeLabel(centre.type)})${centre.tel == null ? '' : '\n${centre.tel}'}',
              ),
            if (user != null) row(Icons.badge_outlined, l10n.referralAgent, user.displayName),
            row(Icons.schedule, l10n.referralDate, formatDateTime(r.referredAt)),
          ],
        );
      },
    );
  }
}
