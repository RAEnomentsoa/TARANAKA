import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../config/clinical_config.dart';
import '../i18n/l10n.dart';
import '../platform/phone_caller.dart';
import '../theme/tokens.dart';
import 'alert_contact.dart';
import 'alert_contact_screen.dart';
import 'danger_sign_info.dart';

/// RED ALERT (spec §5, §6; skill "Alertes"): full screen, opened at once with
/// no animation, works offline.
///
/// Priority: reaching a health service in a minimum of taps. From the top:
/// "URGENCE : consultez immédiatement !", what was reported and where to go,
/// then the saved health centre (name, phone, how to get there) with
/// "Appeler mon centre de santé" (one tap once calls are allowed, through the
/// phone network). Below: "Cette alerte ne remplace pas un diagnostic", the
/// emergency instructions (folded, one tap) and "Fermer l'alerte".
class RedAlertScreen extends StatefulWidget {
  const RedAlertScreen({
    super.key,
    required this.config,
    required this.signs,
    required this.contact,
    this.kind = 'grossesse',
  });

  final ClinicalConfig config;

  /// The signs tapped, as in the configuration (`code`, labels…).
  final List<Map<String, Object?>> signs;

  /// The contact known by the caller; read again from the phone at once.
  final AlertContact contact;

  /// `grossesse`, `post_partum` or `enfant`: where to go.
  final String kind;

  /// Opens the alert immediately (no transition).
  static Future<void> open(
    BuildContext context, {
    required ClinicalConfig config,
    required List<Map<String, Object?>> signs,
    required AlertContact contact,
    String kind = 'grossesse',
  }) {
    HapticFeedback.heavyImpact();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => RedAlertScreen(config: config, signs: signs, contact: contact, kind: kind),
      ),
    );
  }

  @override
  State<RedAlertScreen> createState() => _RedAlertScreenState();
}

class _RedAlertScreenState extends State<RedAlertScreen> {
  late AlertContact _contact = widget.contact;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  /// The contact saved on the phone (encrypted database, no network): the
  /// caller's copy may not be loaded yet.
  Future<void> _reload() async {
    final db = AppScope.maybeRead(context)?.session.active?.db;
    if (db == null) return;
    final contact = await AlertContact.load(db);
    if (mounted) setState(() => _contact = contact);
  }

  Future<void> _call(String number) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await PhoneCaller.call(number);
    if (outcome == CallOutcome.failed) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.alertCallFailed(number))));
    }
  }

  Future<void> _addCentre() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AlertContactScreen()));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final section = widget.config.signesDanger;
    final orientation = localizedText(section['message_orientation'], lang);
    final mention = localizedText(section['mention'], lang);
    final text = Theme.of(context).textTheme;
    const onRed = Colors.white;

    final reported = [
      for (final s in widget.signs)
        DangerSignInfo.reported(s, lang) ?? l10n.alertReported(localizedText(s, lang)),
    ];
    final go = widget.kind == 'enfant' ? l10n.alertGoChild : l10n.alertGoMaternity;

    return Scaffold(
      backgroundColor: AppColors.danger,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xl),
              children: [
                Semantics(
                  liveRegion: true,
                  header: true,
                  label: [l10n.alertEmergencyTitle, ...reported, go].join(' '),
                  child: ExcludeSemantics(
                    // Compact on purpose: the call button must show without
                    // scrolling, even on a small phone.
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_rounded, size: 44, color: onRed),
                            const SizedBox(width: Space.s),
                            Expanded(
                              child: Text(
                                l10n.alertEmergencyTitle,
                                key: const ValueKey('alert-title'),
                                style: text.titleLarge?.copyWith(color: onRed, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.s),
                        for (final r in reported) Text(r, style: text.bodyLarge?.copyWith(color: onRed)),
                        Text(
                          go,
                          key: const ValueKey('alert-go'),
                          style: text.bodyLarge?.copyWith(color: onRed, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.m),
                _centreCard(context),
                const SizedBox(height: Space.l),
                Text(
                  mention.isEmpty ? l10n.alertDisclaimer : mention,
                  key: const ValueKey('alert-disclaimer'),
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: onRed, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Space.m),
                // Emergency instructions: folded, one tap away.
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: const ValueKey('alert-instructions'),
                    iconColor: onRed,
                    collapsedIconColor: onRed,
                    textColor: onRed,
                    collapsedTextColor: onRed,
                    shape: Border.all(color: onRed.withValues(alpha: 0.6)),
                    collapsedShape: Border.all(color: onRed.withValues(alpha: 0.6)),
                    leading: const Icon(Icons.medical_information_outlined, color: onRed),
                    title: Text(l10n.alertInstructions),
                    childrenPadding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.m),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in widget.signs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.s),
                          child: Text(
                            DangerSignInfo.action(s, lang),
                            style: text.bodyLarge?.copyWith(color: onRed),
                          ),
                        ),
                      if (orientation.isNotEmpty)
                        Text(orientation, style: text.bodyLarge?.copyWith(color: onRed)),
                    ],
                  ),
                ),
                const SizedBox(height: Space.xl),
                OutlinedButton(
                  key: const ValueKey('alert-close'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: onRed,
                    side: const BorderSide(color: onRed, width: 2),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.alertClose),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The saved health centre and the call buttons, or how to add it.
  Widget _centreCard(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final c = _contact;
    final bigButton = FilledButton.styleFrom(
      backgroundColor: AppColors.danger,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(Space.touchLarge),
      textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
    final routeQuery = [c.centreName, c.centreDirections].where((s) => s.isNotEmpty).join(', ');

    Widget line(IconData icon, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: Space.s),
          Expanded(
            child: SelectableText(value, key: key, style: text.bodyLarge),
          ),
        ],
      ),
    );

    return Container(
      key: const ValueKey('alert-centre'),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.l)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.local_hospital, color: AppColors.danger),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(l10n.alertCentre, style: text.labelLarge?.copyWith(color: AppColors.textMuted)),
              ),
            ],
          ),
          if (!c.hasCentre && c.agentPhone.isEmpty) ...[
            const SizedBox(height: Space.s),
            Text(l10n.alertNoCentre, style: text.bodyLarge),
            const SizedBox(height: Space.m),
            FilledButton.icon(
              key: const ValueKey('alert-add-centre'),
              style: bigButton,
              onPressed: _addCentre,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: Text(l10n.alertAddCentre),
            ),
          ] else ...[
            if (c.centreName.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(
                c.centreName,
                key: const ValueKey('alert-centre-name'),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
            const SizedBox(height: Space.s),
            if (c.centrePhone.isNotEmpty)
              FilledButton.icon(
                key: const ValueKey('alert-call'),
                style: bigButton,
                onPressed: () => _call(c.centrePhone),
                icon: const Icon(Icons.call),
                label: Text(l10n.alertCallCentre),
              ),
            if (c.centrePhone.isNotEmpty)
              line(Icons.call_outlined, c.centrePhone, key: const ValueKey('alert-centre-phone')),
            if (c.centreDirections.isNotEmpty)
              line(
                Icons.directions_outlined,
                c.centreDirections,
                key: const ValueKey('alert-centre-directions'),
              ),
            if (c.agentPhone.isNotEmpty) ...[
              if (c.centrePhone.isNotEmpty) const SizedBox(height: Space.s),
              c.centrePhone.isEmpty
                  ? FilledButton.icon(
                      key: const ValueKey('alert-call-agent'),
                      style: bigButton,
                      onPressed: () => _call(c.agentPhone),
                      icon: const Icon(Icons.call),
                      label: Text(l10n.alertCallAgent(c.agentPhone)),
                    )
                  : OutlinedButton.icon(
                      key: const ValueKey('alert-call-agent'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger, width: 1.5),
                      ),
                      onPressed: () => _call(c.agentPhone),
                      icon: const Icon(Icons.support_agent),
                      label: Text(l10n.alertCallAgent(c.agentPhone)),
                    ),
            ],
            if (routeQuery.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              TextButton.icon(
                key: const ValueKey('alert-route'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => PhoneCaller.openMap(routeQuery),
                icon: const Icon(Icons.map_outlined),
                label: Text(l10n.alertRoute),
              ),
            ],
            if (c.centrePhone.isEmpty && c.agentPhone.isEmpty)
              TextButton(
                key: const ValueKey('alert-add-phone'),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: _addCentre,
                child: Text(l10n.alertAddPhone),
              ),
          ],
        ],
      ),
    );
  }
}
