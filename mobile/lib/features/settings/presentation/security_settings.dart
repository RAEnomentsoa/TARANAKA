import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/pin_crypto.dart';
import '../../../core/security/profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../profiles/presentation/email_link_form.dart';
import '../../profiles/presentation/recovery_code_card.dart';

/// "Mon code de récupération" (Paramètres): the code of the open profile, to
/// download or copy again, or a new one (the old one then stops working).
class RecoveryCodeScreen extends StatefulWidget {
  const RecoveryCodeScreen({super.key});

  @override
  State<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends State<RecoveryCodeScreen> {
  Future<String?>? _code;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _code ??= AppScope.read(context).session.recoveryCode();
  }

  Future<void> _renew({required bool confirm}) async {
    final l10n = context.l10n;
    final session = AppScope.read(context).session;
    if (confirm) {
      final ok = await confirmAction(
        context,
        message: l10n.recoveryCodeRenewConfirm,
        confirmLabel: l10n.confirm,
      );
      if (!ok) return;
    }
    final code = await session.renewRecoveryCode();
    if (mounted) setState(() => _code = Future.value(code));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = AppScope.of(context).session;
    return FutureBuilder<String?>(
      future: _code,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Scaffold(body: LoadingView());
        final code = snap.data;
        return AppScreen(
          title: l10n.recoveryCodeTitle,
          children: [
            Text(l10n.recoveryCodeHelp),
            const Gap(Space.l),
            if (code == null) ...[
              NoticeBox(icon: Icons.info_outline, text: l10n.recoveryCodeNone),
              const Gap(Space.l),
              FilledButton.icon(
                key: const ValueKey('recovery-code-create'),
                onPressed: () => _renew(confirm: false),
                icon: const Icon(Icons.vpn_key_outlined),
                label: Text(l10n.recoveryCodeCreate),
              ),
            ] else ...[
              RecoveryCodeCard(code: code, profileName: session.active?.info.displayName),
              const Gap(Space.xl),
              TextButton.icon(
                key: const ValueKey('recovery-code-renew'),
                onPressed: () => _renew(confirm: true),
                icon: const Icon(Icons.autorenew),
                label: Text(l10n.recoveryCodeRenew),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// "Déverrouiller avec l'empreinte": shown only when the phone has a
/// fingerprint enrolled. Turning it on asks for the fingerprint first.
class BiometricSettingTile extends StatefulWidget {
  const BiometricSettingTile({super.key});

  @override
  State<BiometricSettingTile> createState() => _BiometricSettingTileState();
}

class _BiometricSettingTileState extends State<BiometricSettingTile> {
  bool? _available;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_available != null) return;
    _available = false;
    AppScope.read(context).services.biometrics.available().then((ok) {
      if (mounted) setState(() => _available = ok);
    });
  }

  Future<void> _toggle(bool on) async {
    final l10n = context.l10n;
    final scope = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    if (on && !await scope.services.biometrics.authenticate(l10n.biometricEnableReason)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await scope.session.setBiometric(on);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(on ? l10n.biometricOn : l10n.biometricOff)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = AppScope.of(context).session.active?.info;
    if (_available != true || info == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const ValueKey('settings-biometric'),
          secondary: const Icon(Icons.fingerprint),
          title: Text(l10n.biometricSetting),
          subtitle: Text(l10n.biometricSettingHint),
          value: info.biometric,
          onChanged: _busy ? null : _toggle,
        ),
        const Divider(),
      ],
    );
  }
}

/// "Récupération par e-mail": its state, opens [EmailRecoveryScreen].
class EmailRecoveryTile extends StatelessWidget {
  const EmailRecoveryTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = AppScope.of(context).session.active?.info;
    if (info == null) return const SizedBox.shrink();
    return ListTile(
      key: const ValueKey('settings-email-recovery'),
      leading: const Icon(Icons.mail_outline),
      title: Text(l10n.emailRecoveryTitle),
      subtitle: Text(emailRecoveryState(context, info)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmailRecoveryScreen())),
    );
  }
}

String emailRecoveryState(BuildContext context, ProfileInfo info) {
  final l10n = context.l10n;
  return switch (info.emailRecovery) {
    EmailRecovery.active => l10n.emailRecoveryActive(info.email ?? ''),
    EmailRecovery.pending => l10n.emailRecoveryPending,
    EmailRecovery.toConfirm => l10n.emailRecoveryToConfirm,
    EmailRecovery.none => l10n.emailRecoveryOff,
  };
}

/// Turn on, retry or confirm the recovery by e-mail of the open profile.
class EmailRecoveryScreen extends StatefulWidget {
  const EmailRecoveryScreen({super.key});

  @override
  State<EmailRecoveryScreen> createState() => _EmailRecoveryScreenState();
}

class _EmailRecoveryScreenState extends State<EmailRecoveryScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  /// "Changer d'adresse": the address field again (pending or to confirm).
  bool _editing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email.text.isEmpty) _email.text = AppScope.read(context).session.active?.info.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AuthError?> Function() action) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    AuthError? error;
    try {
      error = await action();
    } on Object {
      error = AuthError.unknown;
    }
    if (!mounted) return;
    final info = AppScope.read(context).session.active?.info;
    setState(() {
      _busy = false;
      if (info?.emailRecovery != EmailRecovery.none) _editing = false;
      // "Address already used" is not an error here: the screen asks to confirm.
      _error = error == null || error == AuthError.emailInUse ? null : authErrorText(l10n, error);
    });
    if (info?.emailRecovery == EmailRecovery.active) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.emailRecoveryDone)));
    }
  }

  void _enable() {
    final l10n = context.l10n;
    final email = _email.text.trim();
    if (!PinCrypto.isValidEmail(email)) {
      setState(() => _error = l10n.emailInvalid);
      return;
    }
    _run(() => AppScope.read(context).session.enableEmailRecovery(email));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = AppScope.of(context).session;
    final info = session.active?.info;
    if (info == null) return const Scaffold(body: SizedBox.shrink());
    final state = info.emailRecovery;
    return AppScreen(
      title: l10n.emailRecoveryTitle,
      children: [
        Text(l10n.emailRecoveryHelp),
        const Gap(Space.l),
        NoticeBox(
          key: const ValueKey('email-recovery-state'),
          icon: state == EmailRecovery.active ? Icons.check_circle_outline : Icons.info_outline,
          tone: state == EmailRecovery.active ? Tone.success : Tone.info,
          text: emailRecoveryState(context, info),
        ),
        const Gap(Space.l),
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.l),
        ],
        switch (_editing ? EmailRecovery.none : state) {
          EmailRecovery.none => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('email-recovery-address'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: l10n.emailLabel,
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
              ),
              const Gap(Space.m),
              FilledButton(
                key: const ValueKey('email-recovery-enable'),
                onPressed: _busy ? null : _enable,
                child: Text(l10n.emailRecoveryEnable),
              ),
              if (_editing)
                TextButton(
                  key: const ValueKey('email-recovery-cancel-edit'),
                  onPressed: _busy ? null : () => setState(() => _editing = false),
                  child: Text(l10n.cancel),
                ),
            ],
          ),
          EmailRecovery.pending => FilledButton.icon(
            key: const ValueKey('email-recovery-retry'),
            onPressed: _busy ? null : () => _run(session.syncEmailRecovery),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.emailRecoveryRetry),
          ),
          EmailRecovery.toConfirm => EmailLinkForm(
            help: l10n.emailRecoveryConfirmHelp(info.email!),
            sentTo: info.email!,
            submitLabel: l10n.emailRecoveryConfirm,
            onSend: () => session.sendPasswordReset(info.id),
            onSubmit: (password) async {
              final messenger = ScaffoldMessenger.of(context);
              final error = await session.confirmEmailRecovery(password);
              if (error == null) messenger.showSnackBar(SnackBar(content: Text(l10n.emailRecoveryDone)));
              return error;
            },
          ),
          EmailRecovery.active => const SizedBox.shrink(),
        },
        // A mistyped address must not block: it can be replaced.
        if (!_editing && (state == EmailRecovery.pending || state == EmailRecovery.toConfirm)) ...[
          const Gap(Space.s),
          TextButton.icon(
            key: const ValueKey('email-recovery-change'),
            onPressed: _busy
                ? null
                : () => setState(() {
                    _editing = true;
                    _error = null;
                    _email.text = info.email ?? '';
                  }),
            icon: const Icon(Icons.edit_outlined),
            label: Text(l10n.emailRecoveryChange),
          ),
        ],
        if (_busy) ...[const Gap(Space.m), const Center(child: CircularProgressIndicator())],
      ],
    );
  }
}
