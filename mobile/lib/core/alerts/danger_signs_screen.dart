import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../config/clinical_config.dart';
import '../i18n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/screen.dart';
import '../widgets/status_pill.dart';
import 'alert_contact.dart';
import 'danger_sign_info.dart';
import 'red_alert_screen.dart';

/// The danger signs of the configuration (`signes_danger.<kind>`) as large
/// buttons. One tap opens the red alert at once (spec §5: "un seul tap");
/// the contact is loaded in advance so nothing is awaited on tap.
class DangerSignButtons extends StatefulWidget {
  const DangerSignButtons({super.key, required this.kind, this.onSignal});

  /// `enfant`, `grossesse` or `post_partum`.
  final String kind;

  /// Called after the alert opened (e.g. to record the sign); never delays it.
  final Future<void> Function(String code)? onSignal;

  @override
  State<DangerSignButtons> createState() => _DangerSignButtonsState();
}

class _DangerSignButtonsState extends State<DangerSignButtons> {
  AlertContact _contact = const AlertContact();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = AppScope.read(context).session.active?.db;
    if (db != null) {
      AlertContact.load(db).then((c) {
        if (mounted) setState(() => _contact = c);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = AppScope.of(context).services.config.current;
    final signs = asMapList(config.signesDanger[widget.kind]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in signs) ...[
          OutlinedButton(
            key: ValueKey('danger-${s['code']}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              backgroundColor: AppColors.dangerSoft,
              side: const BorderSide(color: AppColors.danger, width: 1.5),
              minimumSize: const Size.fromHeight(Space.touchLarge - 8),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
            ),
            onPressed: () {
              RedAlertScreen.open(context, config: config, signs: [s], contact: _contact, kind: widget.kind);
              widget.onSignal?.call(s['code']! as String);
            },
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded),
                const SizedBox(width: Space.m),
                Expanded(child: Text(localizedText(s, context.lang))),
              ],
            ),
          ),
          const SizedBox(height: Space.s),
        ],
      ],
    );
  }
}

/// The danger signs as one compact, always visible card (Ma grossesse): a
/// clear warning title, then one line per sign. The "Alerte" button of each
/// line opens the red alert at once (one tap, never hidden); tapping the
/// sign itself unfolds what it means and what to do.
class DangerSignsPanel extends StatefulWidget {
  const DangerSignsPanel({super.key, required this.kind, required this.title, this.onSignal});

  /// `grossesse` or `post_partum`.
  final String kind;

  /// Warning title above the list.
  final String title;
  final Future<void> Function(String code)? onSignal;

  @override
  State<DangerSignsPanel> createState() => _DangerSignsPanelState();
}

class _DangerSignsPanelState extends State<DangerSignsPanel> {
  AlertContact _contact = const AlertContact();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = AppScope.read(context).session.active?.db;
    if (db != null) {
      AlertContact.load(db).then((c) {
        if (mounted) setState(() => _contact = c);
      });
    }
  }

  void _alert(ClinicalConfig config, Map<String, Object?> sign) {
    RedAlertScreen.open(context, config: config, signs: [sign], contact: _contact, kind: widget.kind);
    widget.onSignal?.call(sign['code']! as String);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final text = Theme.of(context).textTheme;
    final config = AppScope.of(context).services.config.current;
    final signs = asMapList(config.signesDanger[widget.kind]);
    return Card(
      key: const ValueKey('danger-panel'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.l),
        side: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: the warning, always visible.
          Container(
            color: AppColors.dangerSoft,
            padding: const EdgeInsets.all(Space.l),
            child: Semantics(
              header: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          key: const ValueKey('danger-panel-title'),
                          style: text.titleMedium?.copyWith(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Gap(Space.xs),
                        Text(l10n.dangerPanelHint, style: text.bodyMedium?.copyWith(color: AppColors.text)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
            child: Text(l10n.dangerPanelHowTo, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
          ),
          for (final (i, s) in signs.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: Space.l, endIndent: Space.l),
            ExpansionTile(
              key: ValueKey('danger-item-${s['code']}'),
              controlAffinity: ListTileControlAffinity.leading,
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.only(left: Space.s, right: Space.m),
              childrenPadding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: Text(localizedText(s, lang), style: text.bodyLarge),
              trailing: OutlinedButton.icon(
                key: ValueKey('danger-${s['code']}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  minimumSize: const Size(Space.touch, Space.touch),
                  padding: const EdgeInsets.symmetric(horizontal: Space.m),
                ),
                onPressed: () => _alert(config, s),
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: Text(l10n.dangerAlert),
              ),
              children: [
                if (DangerSignInfo.explanation(s, lang).isNotEmpty) ...[
                  Text(l10n.dangerWhy, style: text.titleSmall),
                  const Gap(Space.xs),
                  Text(DangerSignInfo.explanation(s, lang)),
                  const Gap(Space.m),
                ],
                Text(l10n.dangerTodo, style: text.titleSmall),
                const Gap(Space.xs),
                Text(DangerSignInfo.action(s, lang), key: ValueKey('danger-todo-${s['code']}')),
                const Gap(Space.m),
                FilledButton.icon(
                  key: ValueKey('danger-${s['code']}-open'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  onPressed: () => _alert(config, s),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text(l10n.dangerAlertFull),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.l),
            child: Text(l10n.alertDisclaimer, style: text.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Full screen list of the signs, for the child module.
class DangerSignsScreen extends StatelessWidget {
  const DangerSignsScreen({super.key, required this.kind, required this.title, this.onSignal});

  final String kind;
  final String title;
  final Future<void> Function(String code)? onSignal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      title: title,
      children: [
        NoticeBox(icon: Icons.touch_app_outlined, tone: Tone.danger, text: l10n.dangerSignsHint),
        const Gap(Space.l),
        DangerSignButtons(kind: kind, onSignal: onSignal),
        const Gap(Space.l),
        Text(l10n.alertDisclaimer, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
