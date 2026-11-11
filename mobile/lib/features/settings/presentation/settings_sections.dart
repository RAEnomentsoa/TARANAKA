import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/alert_contact_screen.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile.dart';
import '../../../core/widgets/screen.dart';
import '../../account/presentation/cycle_sharing_tile.dart';
import '../../account/presentation/my_code_screen.dart';
import '../../account/presentation/personal_sync_screen.dart';
import '../../account/presentation/sync_state_pill.dart';

/// Extra settings contributed by the modules.
List<Widget> moduleSettingsSections(BuildContext context) {
  final l10n = context.l10n;
  final active = AppScope.of(context).session.active;
  final profile = active?.info;
  if (profile == null || profile.mode != ProfileMode.personal) return const [];
  final sync = active!.sync;
  void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  return [
    if (sync != null) ...[
      SectionTitle(l10n.settingsOnlineSection),
      Card(
        child: ListenableBuilder(
          listenable: sync,
          builder: (context, _) => Column(
            children: [
              ListTile(
                key: const ValueKey('settings-sync'),
                leading: const Icon(Icons.sync),
                title: Text(l10n.agentSync),
                subtitle: Align(alignment: AlignmentDirectional.centerStart, child: SyncStatePill(sync)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(PersonalSyncScreen(sync: sync)),
              ),
              const Divider(),
              ListTile(
                key: const ValueKey('settings-my-code'),
                leading: const Icon(Icons.qr_code_2),
                title: Text(l10n.myCodeTitle),
                subtitle: Text(sync.account?.identifiant ?? l10n.myCodeNotYet),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(MyCodeScreen(sync: sync)),
              ),
              const Divider(),
              CycleSharingTile(sync: sync),
            ],
          ),
        ),
      ),
    ],
    SectionTitle(l10n.alertTitle),
    Card(
      child: ListTile(
        key: const ValueKey('settings-contact'),
        leading: const Icon(Icons.local_hospital_outlined),
        title: Text(l10n.contactTitle),
        subtitle: Text(l10n.contactHelp),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AlertContactScreen())),
      ),
    ),
  ];
}
