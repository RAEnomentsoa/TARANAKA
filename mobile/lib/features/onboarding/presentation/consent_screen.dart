import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/i18n/language.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import 'privacy_policy_screen.dart';

/// Consent in plain language (spec §3, loi 2014-038), shown right after the
/// profile is created, and once to the profiles created before the sync
/// existed (D16). Personal mode: what is sent to the server and who sees it,
/// the cycle kept private unless shared; consent is given with the explicit
/// "J'accepte et je continue" button. The region is chosen when the profile
/// is created (older profiles without one set it in "Synchronisation").
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _busy = false;
  Future<void> _accept() async {
    final session = AppScope.read(context).session;
    setState(() => _busy = true);
    await session.acceptConsent();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = AppScope.of(context).session;
    final sync = session.active?.sync;
    final personal = sync != null;
    return AppScreen(
      title: l10n.consentTitle,
      leading: IconButton(
        tooltip: l10n.language,
        icon: const Icon(Icons.translate),
        // mg → fr → en → mg.
        onPressed: () {
          final i = appLanguages.indexOf(session.languageCode ?? 'mg');
          session.setLanguage(appLanguages[(i + 1) % appLanguages.length]);
        },
      ),
      bottomAction: FilledButton(
        key: const ValueKey('consent-accept'),
        onPressed: _busy ? null : _accept,
        child: Text(l10n.consentAgree),
      ),
      children: [
        _Point(icon: Icons.edit_note, title: l10n.consentWhatTitle, text: l10n.consentWhat),
        if (personal) ...[
          _Point(icon: Icons.cloud_upload_outlined, title: l10n.consentSyncTitle, text: l10n.consentSync),
          _Point(icon: Icons.water_drop_outlined, title: l10n.consentCycleTitle, text: l10n.consentCycle),
        ] else
          _Point(icon: Icons.shield_outlined, title: l10n.consentWhereTitle, text: l10n.consentWhere),
        _Point(icon: Icons.tune, title: l10n.consentControlTitle, text: l10n.consentControl),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('consent-policy'),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen())),
            icon: const Icon(Icons.policy_outlined),
            label: Text(l10n.privacyPolicyOpen),
          ),
        ),
        const Gap(Space.m),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.s + 2),
            decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: theme.titleMedium),
                Text(text, style: theme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
