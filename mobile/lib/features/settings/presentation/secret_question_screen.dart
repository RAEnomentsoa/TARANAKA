import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile_registry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../profiles/presentation/security_question_form.dart';

/// "Question secrète" in Paramètres (personal profiles): its state, opens
/// [SecretQuestionScreen].
class SecretQuestionTile extends StatelessWidget {
  const SecretQuestionTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = AppScope.of(context).session.active?.info;
    if (info == null) return const SizedBox.shrink();
    return ListTile(
      key: const ValueKey('settings-secret-question'),
      leading: const Icon(Icons.help_outline),
      title: Text(l10n.secretQuestionLabel),
      subtitle: Text(info.hasRecovery ? l10n.secretQuestionOn : l10n.secretQuestionOff),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SecretQuestionScreen())),
    );
  }
}

/// Sets or changes the secret question of the open profile. The current
/// secret code is asked first, so nobody can change it on a phone left
/// unlocked (a wrong code counts like any wrong attempt).
class SecretQuestionScreen extends StatefulWidget {
  const SecretQuestionScreen({super.key});

  @override
  State<SecretQuestionScreen> createState() => _SecretQuestionScreenState();
}

class _SecretQuestionScreenState extends State<SecretQuestionScreen> {
  final _form = GlobalKey<SecurityQuestionFormState>();
  String? _pin;
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    final secret = _form.currentState!.validate();
    if (secret == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await AppScope.read(context).session
        .setRecoveryQuestion(_pin!, secret.question, secret.answer);
    if (!mounted) return;
    switch (result) {
      case Unlocked():
        messenger.showSnackBar(SnackBar(content: Text(l10n.secretQuestionSaved)));
        navigator.pop();
      case WrongPin(:final lockedUntil):
      case LockedOut(until: final DateTime? lockedUntil):
        setState(() {
          _busy = false;
          _pin = null;
          _error = lockedUntil == null
              ? l10n.pinWrong
              : l10n.pinLockedUntil(formatWait(context, lockedUntil.difference(DateTime.now())));
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = AppScope.of(context).session.active?.info;
    final title = Theme.of(context).textTheme.titleLarge;
    return AppScreen(
      title: info?.hasRecovery ?? false ? l10n.secretQuestionChange : l10n.secretQuestionLabel,
      children: [
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.l),
        ],
        if (_pin == null) ...[
          Text(l10n.currentPin, style: title, textAlign: TextAlign.center),
          const Gap(Space.l),
          PinPad(
            key: const ValueKey('secret-question-pin'),
            onCompleted: (pin) => setState(() {
              _pin = pin;
              _error = null;
            }),
          ),
        ] else ...[
          Text(l10n.secretQuestionIntro),
          const Gap(Space.l),
          SecurityQuestionForm(key: _form),
          const Gap(Space.xl),
          FilledButton(
            key: const ValueKey('secret-question-save'),
            onPressed: _busy ? null : _save,
            child: Text(l10n.save),
          ),
          const Gap(Space.l),
        ],
      ],
    );
  }
}
