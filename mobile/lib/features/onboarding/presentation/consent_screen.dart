import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';

/// First launch, step 2: consent in plain language (spec §3, loi 2014-038).
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
        onPressed: () => session.setLanguage(session.languageCode == 'mg' ? 'fr' : 'mg'),
      ),
      bottomAction: FilledButton(
        key: const ValueKey('consent-accept'),
        onPressed: session.acceptConsent,
        child: Text(l10n.consentAgree),
      ),
      children: [
        _Point(icon: Icons.edit_note, title: l10n.consentWhatTitle, text: l10n.consentWhat),
        _Point(icon: Icons.phone_android, title: l10n.consentWhereTitle, text: l10n.consentWhere),
        _Point(icon: Icons.delete_outline, title: l10n.consentEraseTitle, text: l10n.consentErase),
        _Point(icon: Icons.local_hospital_outlined, title: null, text: l10n.consentNotDiagnosis),
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
