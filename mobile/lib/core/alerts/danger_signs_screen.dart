import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../config/clinical_config.dart';
import '../i18n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/screen.dart';
import '../widgets/status_pill.dart';
import 'alert_contact.dart';
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
              final label = localizedText(s, context.lang);
              RedAlertScreen.open(context, config: config, signs: [label], contact: _contact);
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
