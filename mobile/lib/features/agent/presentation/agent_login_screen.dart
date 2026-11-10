import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/pin_crypto.dart';
import '../../../core/security/profile.dart';
import '../../../core/sync/api_client.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../../home/presentation/personal_home_screen.dart';
import '../data/agent_controller.dart';
import 'agent_scope.dart';

/// Agent login with the named account (identifiant + code, spec §2). Needed
/// once, online; afterwards the profile works offline with its local PIN.
/// The server is the one of the app (never typed by the agent).
///
/// Two uses:
/// - [AgentLoginScreen.new]: links an existing agent profile to its account
///   (or logs in again when the session expired);
/// - [AgentLoginScreen.newProfile]: "Agent de santé" chosen as profile type.
///   No name nor PIN to create first: the login creates the agent profile,
///   named after the account and opened with the account code. Only when
///   that code is not 4 digits (the server allows 4 to 6) a 4-digit code for
///   this phone is asked once.
class AgentLoginScreen extends StatefulWidget {
  const AgentLoginScreen({super.key, this.firstLogin = false}) : newProfile = false, onCancel = null;

  const AgentLoginScreen.newProfile({super.key, this.onCancel}) : newProfile = true, firstLogin = false;

  final bool firstLogin;
  final bool newProfile;

  /// New profile on first launch: back returns to the profile type.
  final VoidCallback? onCancel;

  @override
  State<AgentLoginScreen> createState() => _AgentLoginScreenState();
}

class _AgentLoginScreenState extends State<AgentLoginScreen> {
  final _id = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  /// New profile whose account code is not 4 digits: the account, waiting for
  /// the local code, and that code once typed (before its confirmation).
  AgentAccount? _pending;
  String? _localPin;

  @override
  void initState() {
    super.initState();
    if (!widget.newProfile) _id.text = AgentScope.read(context).account?.identifiant ?? '';
  }

  @override
  void dispose() {
    _id.dispose();
    _pin.dispose();
    super.dispose();
  }

  String _message(ApiException e) {
    final l10n = context.l10n;
    return switch (e.code) {
      'offline' => l10n.loginErrorOffline,
      'identifiants_incorrects' => l10n.loginErrorCredentials,
      'compte_bloque' => l10n.loginErrorBlocked,
      'not_agent' => l10n.loginErrorNotAgent,
      'other_account' => l10n.loginErrorOtherAccount,
      _ => l10n.loginErrorServer,
    };
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (_id.text.trim().isEmpty || _pin.text.isEmpty) {
      setState(() => _error = l10n.fieldRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      if (widget.newProfile) {
        await _loginNewProfile();
      } else {
        final agent = AgentScope.read(context);
        await agent.login(
          baseUrl: agent.account?.baseUrl ?? AppScope.read(context).services.defaultApiBaseUrl,
          identifiant: _id.text,
          pin: _pin.text,
          language: context.lang,
        );
        if (!widget.firstLogin && navigator.canPop()) navigator.pop();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } on FormatException {
      if (mounted) setState(() => _error = l10n.loginErrorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Checks the account online, then creates the agent profile.
  Future<void> _loginNewProfile() async {
    final services = AppScope.read(context).services;
    final language = context.lang;
    final api = ApiClient(
      baseUrl: services.defaultApiBaseUrl,
      deviceId: await services.device.id(),
      languageCode: language,
      client: services.httpClient,
    );
    final identifiant = _id.text.trim();
    final (user, tokens) = await api.login(identifiant, _pin.text);
    if (user.profile != 'asc') throw ApiException(403, 'not_agent');
    final account = AgentAccount(baseUrl: api.baseUrl, identifiant: identifiant, user: user, tokens: tokens);
    if (PinCrypto.isValidPin(_pin.text)) {
      await _createProfile(account, _pin.text);
    } else if (mounted) {
      setState(() => _pending = account);
    }
  }

  Future<void> _createProfile(AgentAccount account, String localPin) async {
    final session = AppScope.read(context).session;
    final navigator = Navigator.of(context);
    final name = account.user.displayName.isEmpty ? account.identifiant : account.user.displayName;
    await session.createProfile(
      displayName: name.length > 40 ? name.substring(0, 40) : name,
      pin: localPin,
      mode: ProfileMode.agent,
      // The account is in the profile database before the agent home opens,
      // which then synchronises as after any login.
      prepare: (db) => AgentController.saveAccount(db, account),
    );
    // The gate now shows the agent home of the new profile.
    if (navigator.mounted && navigator.canPop()) navigator.popUntil((r) => r.isFirst);
  }

  void _back() {
    if (_pending != null) {
      setState(() {
        _pending = null;
        _localPin = null;
        _error = null;
      });
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      widget.onCancel?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pending = _pending;
    final canGoBack = pending != null || Navigator.of(context).canPop() || widget.onCancel != null;
    if (!widget.newProfile) return _loginForm(context);
    return PopScope(
      canPop: pending == null && Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: pending == null
          ? _loginForm(
              context,
              leading: canGoBack
                  ? IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: _back)
                  : null,
            )
          : _localPinStep(context, pending),
    );
  }

  Widget _loginForm(BuildContext context, {Widget? leading}) {
    final l10n = context.l10n;
    return AppScreen(
      title: l10n.agentLoginTitle,
      automaticallyImplyLeading: leading == null && !widget.firstLogin && !widget.newProfile,
      leading: leading,
      actions: widget.firstLogin ? homeActions(context) : null,
      bottomAction: FilledButton.icon(
        key: const ValueKey('agent-login-submit'),
        onPressed: _busy ? null : _submit,
        icon: _busy
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.login),
        label: Text(l10n.loginButton),
      ),
      children: [
        NoticeBox(icon: Icons.wifi, text: l10n.agentLoginHelp),
        const Gap(Space.l),
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.l),
        ],
        TextField(
          key: const ValueKey('agent-login-id'),
          controller: _id,
          enabled: !_busy,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.identifiantLabel,
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('agent-login-pin'),
          controller: _pin,
          enabled: !_busy,
          obscureText: true,
          keyboardType: TextInputType.number,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: l10n.serverPinLabel, prefixIcon: const Icon(Icons.password)),
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

  /// Account code of 5 or 6 digits: a 4-digit code to open the profile on
  /// this phone, typed twice.
  Widget _localPinStep(BuildContext context, AgentAccount account) {
    final l10n = context.l10n;
    final first = _localPin;
    return AppScreen(
      title: l10n.agentLoginTitle,
      automaticallyImplyLeading: false,
      leading: IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: _back),
      children: [
        NoticeBox(icon: Icons.lock_outline, text: l10n.agentLocalPinHelp),
        const Gap(Space.l),
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.l),
        ],
        Text(
          first == null ? l10n.pinChoose : l10n.pinConfirm,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const Gap(Space.l),
        PinPad(
          key: ValueKey(first == null ? 'agent-local-pin' : 'agent-local-pin-confirm'),
          enabled: !_busy,
          onCompleted: (pin) async {
            if (first == null) {
              setState(() {
                _localPin = pin;
                _error = null;
              });
            } else if (pin != first) {
              setState(() {
                _localPin = null;
                _error = l10n.pinMismatch;
              });
            } else {
              setState(() => _busy = true);
              try {
                await _createProfile(account, pin);
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            }
          },
        ),
      ],
    );
  }
}
