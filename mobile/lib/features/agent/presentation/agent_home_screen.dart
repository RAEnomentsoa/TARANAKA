import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/config_banner.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../home/presentation/personal_home_screen.dart';
import '../data/agent_controller.dart';
import 'agent_login_screen.dart';
import 'agent_scope.dart';
import 'follow_ups_screen.dart';
import 'referrals_screen.dart';
import 'screening_start_screen.dart';
import 'sync_screen.dart';

/// Agent mode home (spec §3): screen a child, my referrals, follow-ups, sync.
class AgentHomeScreen extends StatefulWidget {
  const AgentHomeScreen({super.key});

  @override
  State<AgentHomeScreen> createState() => _AgentHomeScreenState();
}

class _AgentHomeScreenState extends State<AgentHomeScreen> {
  AgentController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final scope = AppScope.read(context);
    final controller = AgentController(
      services: scope.services,
      database: scope.session.active!.db,
      network: scope.services.network,
      httpClient: scope.services.httpClient,
    );
    _controller = controller;
    final lang = context.lang;
    unawaited(
      controller.init().then((_) {
        // Opportunistic sync when the profile opens; never blocks the screens.
        if (controller.account != null) unawaited(controller.syncNow(language: lang));
      }),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return AgentScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.ready) return const Scaffold(body: LoadingView());
          if (controller.account == null) return const AgentLoginScreen(firstLogin: true);
          return const _AgentHome();
        },
      ),
    );
  }
}

class _AgentHome extends StatelessWidget {
  const _AgentHome();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final agent = AgentScope.of(context);
    final user = agent.account!.user;
    return AppScreen(
      title: l10n.appName,
      automaticallyImplyLeading: false,
      actions: homeActions(context),
      children: [
        Semantics(
          header: true,
          child: Text(l10n.homeGreeting(user.prenom), style: Theme.of(context).textTheme.headlineSmall),
        ),
        const Gap(Space.m),
        const ConfigBanner(),
        const Gap(Space.l),
        BigTile(
          key: const ValueKey('agent-screen'),
          icon: Icons.straighten,
          title: l10n.agentScreen,
          subtitle: l10n.agentScreenHint,
          emphasis: true,
          onTap: () => pushAgent<void>(context, const ScreeningStartScreen()),
        ),
        const Gap(Space.m),
        BigTile(
          key: const ValueKey('agent-referrals'),
          icon: Icons.assignment_outlined,
          title: l10n.agentReferrals,
          onTap: () => pushAgent<void>(context, const ReferralsScreen()),
        ),
        const Gap(Space.m),
        BigTile(
          key: const ValueKey('agent-follow-ups'),
          icon: Icons.event_busy_outlined,
          title: l10n.agentFollowUps,
          onTap: () => pushAgent<void>(context, const FollowUpsScreen()),
        ),
        const Gap(Space.m),
        BigTile(
          key: const ValueKey('agent-sync'),
          icon: agent.syncing
              ? Icons.sync
              : (agent.pending > 0 ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined),
          title: l10n.agentSync,
          subtitle: agent.syncing
              ? l10n.syncRunning
              : (agent.pending > 0 ? l10n.syncPendingCount(agent.pending) : _last(context, agent)),
          onTap: () => pushAgent<void>(context, const SyncScreen()),
        ),
      ],
    );
  }

  String _last(BuildContext context, AgentController agent) => agent.lastSync == null
      ? context.l10n.syncNever
      : context.l10n.syncLast(formatDateTime(agent.lastSync!));
}
