import 'package:flutter/material.dart';

import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';

String classificationLabel(BuildContext context, String? code) {
  final l10n = context.l10n;
  return switch (code) {
    'mas' => l10n.classMas,
    'mam' => l10n.classMam,
    'normal' => l10n.classNormal,
    'nourrisson_a_risque' => l10n.classInfantRisk,
    null => l10n.classNone,
    _ => code,
  };
}

String centreTypeLabel(String? type) => switch (type) {
  'creni' => 'CRENI',
  'crenas' => 'CRENAS',
  'crenam' => 'CRENAM',
  'csb' => 'CSB',
  _ => type ?? '',
};

class ClassificationPill extends StatelessWidget {
  const ClassificationPill(this.code, {super.key});
  final String? code;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = switch (code) {
      'mas' => (Icons.report, Tone.danger),
      'mam' => (Icons.warning_amber, Tone.warning),
      'nourrisson_a_risque' => (Icons.child_friendly, Tone.warning),
      'normal' => (Icons.check_circle_outline, Tone.success),
      _ => (Icons.help_outline, Tone.neutral),
    };
    return StatusPill(icon: icon, label: classificationLabel(context, code), tone: tone);
  }
}

class UrgencyPill extends StatelessWidget {
  const UrgencyPill(this.urgence, {super.key});
  final String? urgence;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (urgence) {
      'rouge' => StatusPill(icon: Icons.emergency, label: l10n.urgencyRed, tone: Tone.danger),
      'orange' => StatusPill(icon: Icons.priority_high, label: l10n.urgencyOrange, tone: Tone.warning),
      'jaune' => StatusPill(icon: Icons.schedule, label: l10n.urgencyYellow, tone: Tone.caution),
      _ => const SizedBox.shrink(),
    };
  }
}

/// "Non transmise — à montrer au centre" until the server acknowledged it,
/// then the lifecycle step.
class ReferralStatusPill extends StatelessWidget {
  const ReferralStatusPill(this.referral, {super.key});
  final Referral referral;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!referral.transmitted) {
      return StatusPill(icon: Icons.outbox_outlined, label: l10n.notTransmitted, tone: Tone.warning);
    }
    return switch (referral.status) {
      'recu' => StatusPill(icon: Icons.how_to_reg, label: l10n.refStatusRecu, tone: Tone.success),
      'pris_en_charge' => StatusPill(
        icon: Icons.medical_services_outlined,
        label: l10n.refStatusPris,
        tone: Tone.success,
      ),
      'en_suivi' => StatusPill(icon: Icons.event_repeat, label: l10n.refStatusSuivi, tone: Tone.info),
      'sortie' => StatusPill(icon: Icons.logout, label: l10n.refStatusSortie, tone: Tone.neutral),
      _ => StatusPill(icon: Icons.send_outlined, label: l10n.transmitted, tone: Tone.info),
    };
  }
}

/// Danger signs of the child, from the configuration.
List<(String code, String label)> childDangerSigns(ClinicalConfig config, String lang) => [
  for (final s in asMapList(config.signesDanger['enfant'])) (s['code']! as String, localizedText(s, lang)),
];
