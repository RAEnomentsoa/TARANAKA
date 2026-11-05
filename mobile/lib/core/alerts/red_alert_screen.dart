import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/clinical_config.dart';
import '../i18n/l10n.dart';
import '../theme/tokens.dart';
import 'alert_contact.dart';

/// RED ALERT (spec §5, §6; skill "Alertes"): full screen, opened at once with
/// no animation, works offline. Always shows what to do, the reference
/// centre, a call button and "Cette alerte ne remplace pas un diagnostic".
class RedAlertScreen extends StatelessWidget {
  const RedAlertScreen({super.key, required this.config, required this.signs, required this.contact});

  final ClinicalConfig config;

  /// Labels of the signs tapped.
  final List<String> signs;
  final AlertContact contact;

  /// Opens the alert immediately (no transition).
  static Future<void> open(
    BuildContext context, {
    required ClinicalConfig config,
    required List<String> signs,
    required AlertContact contact,
  }) {
    HapticFeedback.heavyImpact();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => RedAlertScreen(config: config, signs: signs, contact: contact),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final section = config.signesDanger;
    final go = localizedText(section['message_orientation'], lang);
    final mention = localizedText(section['mention'], lang);
    final text = Theme.of(context).textTheme;
    const onRed = Colors.white;
    final number = contact.callNumber;

    return Scaffold(
      backgroundColor: AppColors.danger,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.all(Space.xl),
              children: [
                Semantics(
                  liveRegion: true,
                  header: true,
                  label: '${l10n.alertTitle}. ${go.isEmpty ? l10n.alertGo : go}',
                  child: Column(
                    children: [
                      const Icon(Icons.warning_rounded, size: 88, color: onRed),
                      const SizedBox(height: Space.m),
                      Text(
                        go.isEmpty ? l10n.alertGo : go,
                        key: const ValueKey('alert-go'),
                        textAlign: TextAlign.center,
                        style: text.headlineSmall?.copyWith(color: onRed, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.l),
                for (final s in signs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: Text(
                      l10n.alertSign(s),
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(color: onRed),
                    ),
                  ),
                const SizedBox(height: Space.l),
                Container(
                  padding: const EdgeInsets.all(Space.l),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Radii.l),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_hospital, color: AppColors.danger),
                          const SizedBox(width: Space.s),
                          Expanded(child: Text(l10n.alertCentre, style: text.titleSmall)),
                        ],
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        contact.centreName.isEmpty ? l10n.alertNoCentre : contact.centreName,
                        style: text.bodyLarge?.copyWith(color: AppColors.text),
                      ),
                      if (number != null) ...[
                        const SizedBox(height: Space.m),
                        FilledButton.icon(
                          key: const ValueKey('alert-call'),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: number)),
                          icon: const Icon(Icons.call),
                          label: Text(l10n.alertCall(number)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.l),
                Text(
                  mention.isEmpty ? l10n.alertDisclaimer : mention,
                  key: const ValueKey('alert-disclaimer'),
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: onRed, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Space.xl),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: onRed,
                    side: const BorderSide(color: onRed, width: 2),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.alertUnderstood),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
