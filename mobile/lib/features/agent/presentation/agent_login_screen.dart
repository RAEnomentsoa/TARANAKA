import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/sync/api_client.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../../home/presentation/personal_home_screen.dart';
import 'agent_scope.dart';

/// Links this profile to the agent's named account (spec §2). Needed once,
/// online; afterwards the profile works offline with its local PIN.
class AgentLoginScreen extends StatefulWidget {
  const AgentLoginScreen({super.key, this.firstLogin = false});

  final bool firstLogin;

  @override
  State<AgentLoginScreen> createState() => _AgentLoginScreenState();
}

class _AgentLoginScreenState extends State<AgentLoginScreen> {
  final _id = TextEditingController();
  final _pin = TextEditingController();
  late final TextEditingController _url;
  bool _busy = false;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final agent = AgentScope.read(context);
    _id.text = agent.account?.identifiant ?? '';
    _url = TextEditingController(
      text: agent.account?.baseUrl ?? AppScope.read(context).services.defaultApiBaseUrl,
    );
  }

  @override
  void dispose() {
    _id.dispose();
    _pin.dispose();
    _url.dispose();
    super.dispose();
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
      await AgentScope.read(context)
          .login(baseUrl: _url.text, identifiant: _id.text, pin: _pin.text, language: context.lang);
      if (!widget.firstLogin && navigator.canPop()) navigator.pop();
    } on ApiException catch (e) {
      setState(
        () => _error = switch (e.code) {
          'offline' => l10n.loginErrorOffline,
          'identifiants_incorrects' => l10n.loginErrorCredentials,
          'compte_bloque' => l10n.loginErrorBlocked,
          'not_agent' => l10n.loginErrorNotAgent,
          'other_account' => l10n.loginErrorOtherAccount,
          _ => l10n.loginErrorServer,
        },
      );
    } on FormatException {
      setState(() => _error = l10n.loginErrorServer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      title: l10n.agentLoginTitle,
      automaticallyImplyLeading: !widget.firstLogin,
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
        const Gap(Space.s),
        TextButton.icon(
          onPressed: () => setState(() => _showServer = !_showServer),
          icon: Icon(_showServer ? Icons.expand_less : Icons.dns_outlined),
          label: Text(l10n.serverUrlLabel),
        ),
        if (_showServer)
          TextField(
            key: const ValueKey('agent-login-url'),
            controller: _url,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(labelText: l10n.serverUrlLabel),
          ),
      ],
    );
  }
}
