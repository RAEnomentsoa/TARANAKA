import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/screen.dart';
import 'language_screen.dart';

/// First launch, step 2, right after the language: "Personnel" or
/// "Agent de santé". The profile creation that follows is set to this type.
class ProfileTypeScreen extends StatelessWidget {
  const ProfileTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = AppScope.of(context).session;
    return AppScreen(
      title: l10n.createProfileTitle,
      automaticallyImplyLeading: false,
      leading: IconButton(
        key: const ValueKey('profile-type-language'),
        tooltip: l10n.language,
        icon: const Icon(Icons.translate),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => LanguageScreen(onChosen: () => Navigator.of(context).pop()),
          ),
        ),
      ),
      children: [
        Text(l10n.modeTitle, style: Theme.of(context).textTheme.titleLarge),
        const Gap(Space.l),
        BigTile(
          key: const ValueKey('type-personal'),
          icon: Icons.family_restroom,
          title: l10n.profilePersonalBadge,
          subtitle: l10n.modePersonalHint,
          onTap: () => session.chooseFirstProfileMode(ProfileMode.personal),
        ),
        const Gap(Space.m),
        BigTile(
          key: const ValueKey('type-agent'),
          icon: Icons.medical_services_outlined,
          title: l10n.profileAgentBadge,
          subtitle: l10n.modeAgentHint,
          onTap: () => session.chooseFirstProfileMode(ProfileMode.agent),
        ),
      ],
    );
  }
}
