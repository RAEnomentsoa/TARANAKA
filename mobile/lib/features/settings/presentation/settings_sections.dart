import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/alert_contact_screen.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile.dart';
import '../../../core/widgets/screen.dart';

/// Extra settings contributed by the modules.
List<Widget> moduleSettingsSections(BuildContext context) {
  final l10n = context.l10n;
  final profile = AppScope.of(context).session.active?.info;
  if (profile == null || profile.mode != ProfileMode.personal) return const [];
  return [
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
