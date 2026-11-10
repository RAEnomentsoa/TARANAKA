import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/i18n/language.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import 'privacy_policy_screen.dart';

/// Consent in plain language (spec §3, loi 2014-038), shown right after the
/// profile is created: "J'accepte et je continue" opens the app, "Consulter la
/// politique de confidentialité" opens the full policy (offline).
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = AppScope.of(context).session;
    return AppScreen(
      title: l10n.consentTitle,
      leading: IconButton(
        tooltip: l10n.language,
        icon: const Icon(Icons.translate),
        // mg → fr → en → mg.
        onPressed: () {
          final i = appLanguages.indexOf(session.languageCode ?? 'mg');
          session.setLanguage(appLanguages[(i + 1) % appLanguages.length]);
        },
      ),
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: const ValueKey('consent-accept'),
            onPressed: session.acceptConsent,
            child: Text(l10n.consentAgree),
          ),
          const Gap(Space.s),
          OutlinedButton.icon(
            key: const ValueKey('consent-policy'),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen())),
            icon: const Icon(Icons.policy_outlined),
            label: Text(l10n.privacyPolicyOpen),
          ),
        ],
      ),
      children: [
        _Point(icon: Icons.edit_note, title: l10n.consentWhatTitle, text: l10n.consentWhat),
        _Point(icon: Icons.shield_outlined, title: l10n.consentWhereTitle, text: l10n.consentWhere),
        _Point(icon: Icons.tune, title: l10n.consentControlTitle, text: l10n.consentControl),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.s + 2),
            decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: theme.titleMedium),
                Text(text, style: theme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
