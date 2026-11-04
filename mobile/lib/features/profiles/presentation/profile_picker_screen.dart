import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/screen.dart';
import '../../onboarding/presentation/create_profile_screen.dart';
import 'unlock_screen.dart';

/// Shared phone (spec §1 P7): each person picks their profile, then types
/// their own PIN. Names only; no health data is shown before unlocking.
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = AppScope.of(context).session;
    return AppScreen(
      title: l10n.profilesTitle,
      automaticallyImplyLeading: false,
      bottomAction: OutlinedButton.icon(
        key: const ValueKey('add-profile'),
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const CreateProfileScreen(canCancel: true))),
        icon: const Icon(Icons.person_add_alt),
        label: Text(l10n.addProfile),
      ),
      children: [
        for (final profile in session.profiles) ...[
          BigTile(
            key: ValueKey('profile-${profile.id}'),
            icon: profile.mode == ProfileMode.agent ? Icons.medical_services_outlined : Icons.person_outline,
            title: profile.displayName,
            subtitle: profile.mode == ProfileMode.agent ? l10n.profileAgentBadge : l10n.profilePersonalBadge,
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => UnlockScreen(profileId: profile.id))),
          ),
          const Gap(Space.m),
        ],
      ],
    );
  }
}
