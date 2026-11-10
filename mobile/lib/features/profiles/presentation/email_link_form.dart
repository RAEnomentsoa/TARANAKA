import 'package:flutter/material.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';

/// The message of a Firebase error, with what to do.
String authErrorText(AppLocalizations l10n, AuthError error) => switch (error) {
  AuthError.offline => l10n.authErrorOffline,
  AuthError.emailInUse => l10n.authErrorEmailInUse,
  AuthError.wrongPassword => l10n.authErrorWrongPassword,
  AuthError.tooManyRequests => l10n.authErrorTooMany,
  AuthError.invalidEmail => l10n.authErrorInvalidEmail,
  AuthError.notConfigured => l10n.authErrorNotConfigured,
  AuthError.noSecret => l10n.authErrorNoSecret,
  AuthError.unknown => l10n.authErrorUnknown,
};

/// "h***@exemple.mg": shown on the locked screens, where anyone holding the
/// phone could read it.
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return email;
  return '${email[0]}***${email.substring(at)}';
}

/// The standard Firebase reset link, then the password chosen on its page:
/// "Envoyer le lien" → e-mail sent → password → [submitLabel].
/// [onSubmit] returns null when it worked, or the error to show.
class EmailLinkForm extends StatefulWidget {
  const EmailLinkForm({
    super.key,
    required this.help,
    required this.sentTo,
    required this.onSend,
    required this.onSubmit,
    required this.submitLabel,
  });

  final String help;

  /// The address as shown in "E-mail envoyé à …".
  final String sentTo;
  final Future<AuthResult<void>> Function() onSend;
  final Future<AuthError?> Function(String password) onSubmit;
  final String submitLabel;

  @override
  State<EmailLinkForm> createState() => _EmailLinkFormState();
}

class _EmailLinkFormState extends State<EmailLinkForm> {
  final _password = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  bool _hidden = true;
  AuthError? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onSend();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = _sent || result.isOk;
      _error = result.error;
    });
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(_password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.help),
        const Gap(Space.l),
        if (_error != null) ...[
          NoticeBox(
            key: const ValueKey('email-error'),
            icon: Icons.error_outline,
            tone: Tone.danger,
            text: authErrorText(l10n, _error!),
          ),
          const Gap(Space.l),
        ],
        if (!_sent)
          FilledButton.icon(
            key: const ValueKey('email-send'),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.forward_to_inbox_outlined),
            label: Text(l10n.emailResetSend),
          )
        else ...[
          NoticeBox(
            key: const ValueKey('email-sent'),
            icon: Icons.mark_email_read_outlined,
            tone: Tone.success,
            text: l10n.emailResetSent(widget.sentTo),
          ),
          const Gap(Space.l),
          TextField(
            key: const ValueKey('email-password'),
            controller: _password,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.emailPasswordLabel,
              prefixIcon: const Icon(Icons.password_outlined),
              suffixIcon: IconButton(
                tooltip: _hidden ? l10n.emailPasswordShow : l10n.emailPasswordHide,
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          const Gap(Space.l),
          FilledButton(
            key: const ValueKey('email-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(widget.submitLabel),
          ),
          const Gap(Space.s),
          TextButton.icon(
            key: const ValueKey('email-resend'),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.emailResetResend),
          ),
        ],
        if (_busy) ...[const Gap(Space.m), const Center(child: CircularProgressIndicator())],
      ],
    );
  }
}
