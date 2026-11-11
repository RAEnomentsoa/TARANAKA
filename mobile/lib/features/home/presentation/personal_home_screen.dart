import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/security/profile.dart';
import '../../../core/widgets/screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'module_routes.dart';
import 'notification_bell.dart';
import 'reminders.dart';

/// Personal mode home (spec §3): three illustrated tiles, plus the agent tile
/// that only opens with professional credentials.
class PersonalHomeScreen extends StatelessWidget {
  const PersonalHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = AppScope.of(context).session;
    final name = session.active?.info.displayName ?? '';
    // Back on the home, a module may have changed the reminders.
    Future<void> open(Widget screen) async {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
      remindersRevision.value++;
    }

    return AppScreen(
      title: l10n.appName,
      automaticallyImplyLeading: false,
      actions: homeActions(context),
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.homeGreeting(name),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        // Reminders are behind the bell of the header only; the sync state
        // ("Sur ce téléphone seulement"…) is in Settings only.
        const Gap(Space.xl),
        BigTile(
          key: const ValueKey('tile-cycle'),
          icon: Icons.water_drop_outlined,
          title: l10n.tileCycle,
          onTap: () => open(ModuleRoutes.cycle()),
        ),
        const Gap(Space.m),
        BigTile(
          key: const ValueKey('tile-pregnancy'),
          icon: Icons.pregnant_woman,
          title: l10n.tilePregnancy,
          onTap: () => open(ModuleRoutes.pregnancy()),
        ),
        const Gap(Space.m),
        BigTile(
          key: const ValueKey('tile-child'),
          icon: Icons.child_care,
          title: l10n.tileChild,
          onTap: () => open(ModuleRoutes.child()),
        ),
        const Gap(Space.xl),
        BigTile(
          key: const ValueKey('tile-agent'),
          icon: Icons.lock_outline,
          title: l10n.tileAgent,
          subtitle: l10n.tileAgentHint,
          onTap: () => open(ModuleRoutes.agentAccess()),
        ),
      ],
    );
  }
}

/// The home header, in this order: the bell (personal profiles, whose
/// reminders it lists), Settings, then the padlock.
List<Widget> homeActions(BuildContext context) {
  final l10n = context.l10n;
  final personal = AppScope.read(context).session.active?.info.mode == ProfileMode.personal;
  return [
    if (personal) const NotificationBell(),
    IconButton(
      key: const ValueKey('open-settings'),
      tooltip: l10n.settings,
      icon: const Icon(Icons.settings_outlined),
      onPressed: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
    ),
    IconButton(
      key: const ValueKey('lock-now'),
      tooltip: l10n.lockNow,
      icon: const Icon(Icons.lock_outline),
      onPressed: AppScope.read(context).session.lock,
    ),
  ];
}
