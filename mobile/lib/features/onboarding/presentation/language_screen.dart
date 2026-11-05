import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/screen.dart';

/// First launch, step 1 (spec §3). Both choices are written in their own
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
        const Icon(Icons.translate, size: 48, color: AppColors.accent),
        const Gap(Space.l),
        Text(
          'Safidio ny fiteny\nChoisissez votre langue',
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
        const Gap(Space.l),
        if (session.languageCode != null)
          Text(
            context.l10n.malagasyReviewNote,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
