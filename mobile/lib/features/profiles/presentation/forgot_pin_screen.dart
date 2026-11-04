import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile.dart';
import '../../../core/security/profile_registry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';

/// Forgotten PIN (spec §8).
/// - Personal mode with a recovery question: answer, then a new PIN; data kept.
/// - Personal mode without one: reset, with loss of the local data, clearly said.
/// - Agent mode: the supervisor resets the server PIN; the local profile is
///   deleted and synced data comes back at the next login.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.profileId});

  final String profileId;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final _answer = TextEditingController();
  bool _choosingPin = false;
  String? _newPin;
  String? _error;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  ProfileInfo _profile() =>
      AppScope.read(context).session.profiles.firstWhere((p) => p.id == widget.profileId);

  Future<void> _reset() async {
    final l10n = context.l10n;
    final profile = _profile();
    final navigator = Navigator.of(context);
    final session = AppScope.read(context).session;
    final ok = await confirmAction(
      context,
      message: l10n.resetProfileConfirm(profile.displayName),
      confirmLabel: l10n.erase,
      destructive: true,
    );
    if (!ok) return;
    await session.deleteProfile(profile.id);
    navigator.popUntil((r) => r.isFirst);
  }

  Future<void> _recover(String confirmPin) async {
    final l10n = context.l10n;
    if (confirmPin != _newPin) {
      setState(() {
        _newPin = null;
        _error = l10n.pinMismatch;
      });
      return;
    }
    final navigator = Navigator.of(context);
    final result = await AppScope.read(context).session.recover(widget.profileId, _answer.text, confirmPin);
    if (!mounted) return;
    switch (result) {
      case Unlocked():
        navigator.popUntil((r) => r.isFirst);
      case WrongPin(:final lockedUntil):
      case LockedOut(until: final DateTime? lockedUntil):
        setState(() {
          _choosingPin = false;
          _newPin = null;
          _error = lockedUntil == null
              ? l10n.answerWrong
              : l10n.pinLockedUntil(formatWait(context, lockedUntil.difference(DateTime.now())));
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = _profile();
    final resetButton = OutlinedButton.icon(
      key: const ValueKey('reset-profile'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.danger,
        side: const BorderSide(color: AppColors.danger),
      ),
      onPressed: _reset,
      icon: const Icon(Icons.delete_forever_outlined),
      label: Text(l10n.resetProfile),
    );

    if (profile.mode == ProfileMode.agent) {
      return AppScreen(
        title: l10n.forgotPin,
        children: [
          NoticeBox(icon: Icons.support_agent, text: l10n.forgotPinAgent),
          const Gap(Space.xl),
          resetButton,
        ],
      );
    }
    if (!profile.hasRecovery) {
      return AppScreen(
        title: l10n.forgotPin,
        children: [
          NoticeBox(icon: Icons.warning_amber, tone: Tone.warning, text: l10n.forgotPinNoRecovery),
          const Gap(Space.xl),
          resetButton,
        ],
      );
    }

    final title = Theme.of(context).textTheme.titleLarge;
    return AppScreen(
      title: l10n.forgotPin,
      bottomAction: _choosingPin
          ? null
          : FilledButton(
              key: const ValueKey('recovery-continue'),
              onPressed: () {
                if (_answer.text.trim().isNotEmpty) {
                  setState(() {
                    _choosingPin = true;
                    _error = null;
                  });
                }
              },
              child: Text(l10n.continueLabel),
            ),
      children: [
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.l),
        ],
        if (!_choosingPin) ...[
          Text(l10n.forgotPinRecovery),
          const Gap(Space.l),
          Text(profile.recoveryQuestion!, style: title),
          const Gap(Space.m),
          TextField(
            key: const ValueKey('recovery-answer-input'),
            controller: _answer,
            decoration: InputDecoration(labelText: l10n.recoveryAnswerLabel),
          ),
        ] else ...[
          Text(_newPin == null ? l10n.newPin : l10n.pinConfirm, style: title, textAlign: TextAlign.center),
          const Gap(Space.l),
          PinPad(
            key: ValueKey(_newPin == null ? 'new' : 'confirm'),
            onCompleted: (pin) {
              if (_newPin == null) {
                setState(() => _newPin = pin);
              } else {
                _recover(pin);
              }
            },
          ),
        ],
        const Gap(Space.xxl),
        resetButton,
      ],
    );
  }
}
