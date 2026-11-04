import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../config/clinical_config.dart';
import '../i18n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/screen.dart';
import '../widgets/status_pill.dart';
import 'alert_contact.dart';
import 'red_alert_screen.dart';

/// List of danger signs from the configuration (`signes_danger.<kind>`).
/// One tap on a sign opens the red alert at once (spec §5: "un seul tap").
class DangerSignsScreen extends StatefulWidget {
  const DangerSignsScreen({super.key, required this.kind, required this.title, this.onSignal});

  /// `enfant`, `grossesse` or `post_partum`.
  final String kind;
  final String title;

  /// Called after the alert opened (e.g. to record the sign); never delays it.
  final Future<void> Function(String code)? onSignal;

  @override
  State<DangerSignsScreen> createState() => _DangerSignsScreenState();
}

class _DangerSignsScreenState extends State<DangerSignsScreen> {
  AlertContact _contact = const AlertContact();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final db = AppScope.read(context).session.active?.db;
    if (db != null) {
      // Loaded in advance so the alert opens without waiting.
      AlertContact.load(db).then((c) {
        if (mounted) setState(() => _contact = c);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = AppScope.of(context).services.config.current;
    final signs = asMapList(config.signesDanger[widget.kind]);
    return AppScreen(
      title: widget.title,
      children: [
        NoticeBox(icon: Icons.touch_app_outlined, tone: Tone.danger, text: l10n.dangerSignsHint),
        const Gap(Space.l),
        for (final s in signs) ...[
          Semantics(
            button: true,
            child: OutlinedButton(
              key: ValueKey('danger-${s['code']}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                backgroundColor: AppColors.dangerSoft,
                side: const BorderSide(color: AppColors.danger, width: 1.5),
                minimumSize: const Size.fromHeight(Space.touchLarge),
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
          ),
          const Gap(Space.s),
        ],
        const Gap(Space.l),
        Text(l10n.alertDisclaimer, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
