import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';

/// Privacy policy in plain language, in the app (works offline): opened from
/// the consent screen and from the settings.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final sections = [
      (Icons.edit_note, l10n.policyDataTitle, l10n.policyData),
      (Icons.lock_outline, l10n.policyStorageTitle, l10n.policyStorage),
      (Icons.share_outlined, l10n.policySharingTitle, l10n.policySharing),
      (Icons.manage_accounts_outlined, l10n.policyRightsTitle, l10n.policyRights),
      (Icons.gavel_outlined, l10n.policyLawTitle, l10n.policyLaw),
      (Icons.local_hospital_outlined, l10n.policyHealthTitle, l10n.policyHealth),
    ];
    return AppScreen(
      title: l10n.privacyPolicyTitle,
      children: [
        Text(l10n.policyIntro, key: const ValueKey('privacy-policy'), style: text.bodyLarge),
        for (final (icon, title, body) in sections) ...[
          const Gap(Space.l),
          Semantics(
            header: true,
            child: Row(
              children: [
                Icon(icon, color: AppColors.accent),
                const SizedBox(width: Space.s),
                Expanded(child: Text(title, style: text.titleMedium)),
              ],
            ),
          ),
          const Gap(Space.xs),
          Text(body, style: text.bodyLarge),
        ],
      ],
    );
  }
}
