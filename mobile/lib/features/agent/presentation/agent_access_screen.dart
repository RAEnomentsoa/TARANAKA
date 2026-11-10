import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import 'agent_login_screen.dart';

/// Personal mode, 4th tile (spec §3): the malnutrition module is not
/// reachable without professional credentials. It lives in a separate agent
/// profile, so a mother's data and an agent's patients never mix.
class AgentAccessScreen extends StatelessWidget {
  const AgentAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      title: l10n.tileAgent,
      bottomAction: FilledButton.icon(
        key: const ValueKey('agent-access-create'),
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const AgentLoginScreen.newProfile())),
        icon: const Icon(Icons.medical_services_outlined),
        label: Text(l10n.agentAccessCreate),
      ),
      children: [
        const Icon(Icons.lock_outline, size: 48, color: AppColors.accent),
        const Gap(Space.l),
        NoticeBox(icon: Icons.badge_outlined, text: l10n.agentAccessText),
      ],
    );
  }
}
