import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import 'change_pin_screen.dart';
import 'settings_sections.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final session = scope.session;
    final config = scope.services.config.current;
    final active = session.active;
    if (active == null) return const SizedBox.shrink();

    Future<void> eraseAll() async {
      final navigator = Navigator.of(context);
      final ok = await confirmAction(
        context,
        message: l10n.eraseAllConfirm,
        confirmLabel: l10n.erase,
        destructive: true,
      );
      if (!ok) return;
      await session.deleteProfile(active.info.id);
      navigator.popUntil((r) => r.isFirst);
    }

    return AppScreen(
      title: l10n.settings,
      children: [
        SectionTitle(l10n.language),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'mg', label: Text(l10n.languageMalagasy)),
            ButtonSegment(value: 'fr', label: Text(l10n.languageFrench)),
          ],
          selected: {session.languageCode ?? 'fr'},
          onSelectionChanged: (s) => session.setLanguage(s.first),
        ),
        const Gap(Space.s),
        Text(l10n.malagasyReviewNote, style: Theme.of(context).textTheme.bodySmall),
        ...moduleSettingsSections(context),
        SectionTitle(l10n.privacyTitle),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const ValueKey('settings-change-pin'),
                leading: const Icon(Icons.password),
                title: Text(l10n.changePin),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const ChangePinScreen())),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.switch_account_outlined),
                title: Text(l10n.switchProfile),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await session.lock();
                  navigator.popUntil((r) => r.isFirst);
                },
              ),
              const Divider(),
              ListTile(
                key: const ValueKey('settings-erase'),
                leading: const Icon(Icons.delete_forever_outlined, color: AppColors.danger),
                title: Text(l10n.eraseAll, style: const TextStyle(color: AppColors.danger)),
                onTap: eraseAll,
              ),
            ],
          ),
        ),
        SectionTitle(l10n.aboutTitle),
        Text(l10n.aboutConfig(config.version)),
        if (config.toValidate) ...[const Gap(Space.xs), Text(l10n.configToValidate(config.version))],
      ],
    );
  }
}
