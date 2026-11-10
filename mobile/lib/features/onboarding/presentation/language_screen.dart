import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/screen.dart';

/// First launch, step 1 (spec §3). Every choice is written in its own
/// language, so the screen works before any choice is made.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key, this.onChosen});

  /// When opened from the settings, pops instead of moving the onboarding on.
  final VoidCallback? onChosen;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    Future<void> choose(String code) async {
      await session.setLanguage(code);
      onChosen?.call();
    }

    return AppScreen(
      children: [
        const Gap(Space.xl),
        // First launch: the app's logo welcomes the user. From the settings,
        // the screen is only a language choice, so it keeps its plain icon.
        // The logo image already carries the app's name.
        if (onChosen == null)
          Image.asset('assets/images/logo_v1.png', width: 180, height: 180, excludeFromSemantics: true)
        else
          const Icon(Icons.translate, size: 48, color: AppColors.accent),
        if (onChosen == null) ...[
          const Gap(Space.m),
          // What the app is for, before any choice: in the three languages.
          Text(
            'Fanaraha-maso ny fahasalaman’ny reny sy ny zaza\n'
            'Le suivi santé de la mère et de l’enfant\n'
            'Health follow-up for mother and child',
            key: const ValueKey('app-intro-short'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ],
        const Gap(Space.l),
        Text(
          'Safidio ny fiteny\nChoisissez votre langue\nChoose your language',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Gap(Space.xl),
        BigTile(
          key: const ValueKey('lang-mg'),
          icon: Icons.record_voice_over_outlined,
          title: 'Malagasy',
          emphasis: session.languageCode == 'mg',
          onTap: () => choose('mg'),
        ),
        const Gap(Space.m),
        BigTile(
          key: const ValueKey('lang-fr'),
          icon: Icons.chat_bubble_outline,
          title: 'Français',
          emphasis: session.languageCode == 'fr',
          onTap: () => choose('fr'),
        ),
        const Gap(Space.m),
        BigTile(
          key: const ValueKey('lang-en'),
          icon: Icons.language,
          title: 'English',
          emphasis: session.languageCode == 'en',
          onTap: () => choose('en'),
        ),
        const Gap(Space.l),
        if (session.languageCode == 'mg')
          Text(
            context.l10n.malagasyReviewNote,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
