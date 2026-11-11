import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../../agent/data/agent_controller.dart';
import '../data/personal_sync_controller.dart';

/// "Mon code" (D16): her login and her code, with a QR code, to show a
/// health agent so he opens her file. Available offline once the account
/// exists (it is created at the first sync with network).
class MyCodeScreen extends StatelessWidget {
  const MyCodeScreen({super.key, required this.sync});

  final PersonalSyncController sync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final l10n = context.l10n;
        final text = Theme.of(context).textTheme;
        final account = sync.account;
        if (account == null || account.code.isEmpty) {
          return AppScreen(
            title: l10n.myCodeTitle,
            children: [NoticeBox(icon: Icons.cloud_off_outlined, tone: Tone.info, text: l10n.myCodeNotYet)],
          );
        }
        return AppScreen(
          title: l10n.myCodeTitle,
          children: [
            Text(l10n.myCodeIntro, style: text.bodyLarge),
            const Gap(Space.l),
            Center(
              child: Semantics(
                label: l10n.myCodeQrLabel,
                image: true,
                child: Container(
                  key: const ValueKey('my-code-qr'),
                  padding: const EdgeInsets.all(Space.m),
                  color: AppColors.surface,
                  child: QrImageView(
                    data: beneficiaryQrData(account.code),
                    size: 220,
                    backgroundColor: AppColors.surface,
                  ),
                ),
              ),
            ),
            const Gap(Space.l),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.pin_outlined, color: AppColors.accent),
                    title: SelectableText(
                      account.code,
                      key: const ValueKey('my-code'),
                      style: text.headlineSmall,
                    ),
                    subtitle: Text(l10n.myCodeCode),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.person_outline, color: AppColors.accent),
                    title: SelectableText(
                      account.identifiant,
                      key: const ValueKey('my-identifier'),
                      style: text.titleMedium,
                    ),
                    subtitle: Text(l10n.myCodeIdentifier),
                  ),
                ],
              ),
            ),
            const Gap(Space.m),
            Text(l10n.myCodeLoginHint, style: text.bodySmall),
          ],
        );
      },
    );
  }
}
