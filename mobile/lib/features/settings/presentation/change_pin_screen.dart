import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile_registry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  String? _current;
  String? _new;
  String? _error;

  Future<void> _finish(String confirm) async {
    final l10n = context.l10n;
    if (confirm != _new) {
      setState(() {
        _new = null;
        _error = l10n.pinMismatch;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await AppScope.read(context).session.changePin(_current!, _new!);
    if (!mounted) return;
    switch (result) {
      case Unlocked():
        messenger.showSnackBar(SnackBar(content: Text(l10n.pinChanged)));
        navigator.pop();
      case WrongPin(:final lockedUntil):
      case LockedOut(until: final DateTime? lockedUntil):
        setState(() {
          _current = null;
          _new = null;
          _error = lockedUntil == null
              ? l10n.pinWrong
              : l10n.pinLockedUntil(formatWait(context, lockedUntil.difference(DateTime.now())));
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final step = _current == null ? 0 : (_new == null ? 1 : 2);
    final label = [l10n.currentPin, l10n.newPin, l10n.pinConfirm][step];
    return AppScreen(
      title: l10n.changePin,
      children: [
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.l),
        ],
        Text(label, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const Gap(Space.l),
        PinPad(
          key: ValueKey('change-pin-$step'),
          onCompleted: (pin) {
            setState(() => _error = null);
            if (step == 0) {
              setState(() => _current = pin);
            } else if (step == 1) {
              setState(() => _new = pin);
            } else {
              _finish(pin);
            }
          },
        ),
      ],
    );
  }
}
