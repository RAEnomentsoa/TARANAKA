import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile.dart';
import '../../../core/security/profile_registry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import 'email_link_form.dart';

enum _Method { code, question, email }

/// "Code oublié ?" (spec §8).
/// - Personal mode: the recovery code (downloaded at the creation), or the
///   recovery question of an older profile, or the standard Firebase reset
///   link sent to the e-mail address (password chosen on its page, then typed
///   here), then a new secret code; data kept.
/// - Without any of them: reset, with loss of the local data, clearly said.
/// - Agent mode: the supervisor resets the server PIN; the local profile is
///   deleted and synced data comes back at the next login.
/// Wrong codes and answers count like wrong PINs (5 attempts, then a delay).
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.profileId});

  final String profileId;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final _secret = TextEditingController();
  _Method? _method;
  bool _choosingPin = false;
  String? _newPin;
  String? _error;

  /// Read from Firestore after the sign-in (recovery by e-mail).
  List<int>? _emailSecret;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  ProfileInfo _profile() =>
      AppScope.read(context).session.profiles.firstWhere((p) => p.id == widget.profileId);

  void _choose(_Method? method) => setState(() {
    _method = method;
    _choosingPin = false;
    _newPin = null;
    _error = null;
    _emailSecret = null;
    _secret.clear();
  });

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
    final session = AppScope.read(context).session;
    final result = switch (_method!) {
      _Method.code => await session.recoverWithCode(widget.profileId, _secret.text, confirmPin),
      _Method.question => await session.recover(widget.profileId, _secret.text, confirmPin),
      _Method.email => await session.recoverWithEmailSecret(widget.profileId, _emailSecret!, confirmPin),
    };
    if (!mounted) return;
    switch (result) {
      case Unlocked():
        navigator.popUntil((r) => r.isFirst);
      case WrongPin(:final lockedUntil):
      case LockedOut(until: final DateTime? lockedUntil):
        setState(() {
          _choosingPin = false;
          _newPin = null;
          _error = lockedUntil != null
              ? l10n.pinLockedUntil(formatWait(context, lockedUntil.difference(DateTime.now())))
              : switch (_method!) {
                  _Method.code => l10n.recoveryCodeWrong,
                  _Method.question => l10n.answerWrong,
                  _Method.email => l10n.authErrorNoSecret,
                };
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

    if (profile.mode == ProfileMode.agent && !profile.hasRecoveryCode) {
      return AppScreen(
        title: l10n.forgotPin,
        children: [
          NoticeBox(icon: Icons.support_agent, text: l10n.forgotPinAgent),
          const Gap(Space.xl),
          resetButton,
        ],
      );
    }
    if (!profile.hasRecovery && !profile.hasRecoveryCode && !profile.hasEmailRecovery) {
      return AppScreen(
        title: l10n.forgotPin,
        children: [
          NoticeBox(icon: Icons.warning_amber, tone: Tone.warning, text: l10n.forgotPinNoRecovery),
          const Gap(Space.xl),
          resetButton,
        ],
      );
    }

    final method = _method;
    return PopScope(
      // Back from a method: the list of methods again.
      canPop: method == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _choose(null);
      },
      child: method == null ? _methods(context, profile, resetButton) : _withSecret(context, profile, method),
    );
  }

  /// How to get back in: the recovery code, the question, the e-mail.
  Widget _methods(BuildContext context, ProfileInfo profile, Widget resetButton) {
    final l10n = context.l10n;
    return AppScreen(
      title: l10n.forgotPin,
      children: [
        Text(l10n.forgotPinChoose, style: Theme.of(context).textTheme.titleLarge),
        const Gap(Space.l),
        if (profile.hasRecoveryCode) ...[
          BigTile(
            key: const ValueKey('forgot-with-code'),
            icon: Icons.vpn_key_outlined,
            title: l10n.forgotWithCode,
            subtitle: l10n.forgotWithCodeHint,
            onTap: () => _choose(_Method.code),
          ),
          const Gap(Space.m),
        ],
        if (profile.hasRecovery) ...[
          BigTile(
            key: const ValueKey('forgot-with-question'),
            icon: Icons.help_outline,
            title: l10n.forgotWithQuestion,
            subtitle: profile.recoveryQuestion,
            onTap: () => _choose(_Method.question),
          ),
          const Gap(Space.m),
        ],
        // By e-mail: the standard Firebase reset link (needs Internet).
        if (profile.hasEmailRecovery && profile.emailRecovery == EmailRecovery.active) ...[
          BigTile(
            key: const ValueKey('forgot-with-email'),
            icon: Icons.mail_outline,
            title: l10n.forgotWithEmail,
            subtitle: l10n.forgotWithEmailHint(maskEmail(profile.email!)),
            onTap: () => _choose(_Method.email),
          ),
          const Gap(Space.m),
        ] else if (profile.email != null) ...[
          NoticeBox(
            key: const ValueKey('forgot-email-inactive'),
            icon: Icons.mail_outline,
            text: l10n.forgotEmailNotActive,
          ),
          const Gap(Space.m),
        ],
        const Gap(Space.xl),
        Text(l10n.forgotPinLastResort, style: Theme.of(context).textTheme.bodySmall),
        const Gap(Space.s),
        resetButton,
      ],
    );
  }

  /// The code (or answer), then the new secret code twice.
  Widget _withSecret(BuildContext context, ProfileInfo profile, _Method method) {
    final l10n = context.l10n;
    final title = Theme.of(context).textTheme.titleLarge;
    final isCode = method == _Method.code;
    final isEmail = method == _Method.email;
    return AppScreen(
      title: l10n.forgotPin,
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: l10n.back,
        icon: const Icon(Icons.arrow_back),
        onPressed: () => _choosingPin ? setState(() => _choosingPin = false) : _choose(null),
      ),
      bottomAction: _choosingPin || isEmail
          ? null
          : FilledButton(
              key: const ValueKey('recovery-continue'),
              onPressed: () {
                if (_secret.text.trim().isNotEmpty) {
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
          if (isEmail)
            EmailLinkForm(
              help: l10n.emailResetHelp(maskEmail(profile.email!)),
              sentTo: maskEmail(profile.email!),
              submitLabel: l10n.continueLabel,
              onSend: () => AppScope.read(context).session.sendPasswordReset(profile.id),
              onSubmit: (password) async {
                final result = await AppScope.read(context).session.fetchEmailSecret(profile.id, password);
                if (!result.isOk) return result.error;
                if (mounted) {
                  setState(() {
                    _emailSecret = result.value;
                    _choosingPin = true;
                    _error = null;
                  });
                }
                return null;
              },
            )
          else if (isCode) ...[
            Text(l10n.forgotWithCodeHelp),
            const Gap(Space.l),
            TextField(
              key: const ValueKey('recovery-code-input'),
              controller: _secret,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5),
              decoration: InputDecoration(
                labelText: l10n.recoveryCodeLabel,
                hintText: 'XXXX',
                prefixIcon: const Icon(Icons.vpn_key_outlined),
              ),
            ),
          ] else ...[
            Text(l10n.forgotPinRecovery),
            const Gap(Space.l),
            Text(profile.recoveryQuestion!, style: title),
            const Gap(Space.m),
            TextField(
              key: const ValueKey('recovery-answer-input'),
              controller: _secret,
              decoration: InputDecoration(labelText: l10n.recoveryAnswerLabel),
            ),
          ],
        ] else ...[
          Text(_newPin == null ? l10n.pinChoose : l10n.pinConfirm, style: title, textAlign: TextAlign.center),
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
      ],
    );
  }
}
