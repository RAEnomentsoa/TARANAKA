import 'package:flutter/material.dart';

import '../../onboarding/presentation/privacy_policy_screen.dart';
import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import 'change_pin_screen.dart';
import 'secret_question_screen.dart';
import 'security_settings.dart';
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
        // Each language is written in itself, so it can be found from any other.
        Card(
          child: RadioGroup<String>(
            groupValue: session.languageCode ?? 'fr',
            onChanged: (v) {
              if (v != null) session.setLanguage(v);
            },
            child: Column(
              children: [
                for (final (code, label) in [('mg', 'Malagasy'), ('fr', 'Français'), ('en', 'English')])
                  RadioListTile<String>(
                    key: ValueKey('settings-lang-$code'),
                    value: code,
                    title: Text(label),
                  ),
              ],
            ),
          ),
        ),
        if (session.languageCode == 'mg') ...[
          const Gap(Space.s),
          Text(l10n.malagasyReviewNote, style: Theme.of(context).textTheme.bodySmall),
        ],
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
              // Personal profiles: the recovery by e-mail (Firebase Auth).
              if (session.active?.info.mode != ProfileMode.agent) ...[
                const SecretQuestionTile(),
                const Divider(),
                const EmailRecoveryTile(),
                const Divider(),
              ],
              const BiometricSettingTile(),
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
                key: const ValueKey('settings-privacy-policy'),
                leading: const Icon(Icons.policy_outlined),
                title: Text(l10n.privacyPolicyTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen())),
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
