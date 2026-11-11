import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import 'agent_scope.dart';
import 'screening_start_screen.dart';

/// Registers a woman who has no phone (cahier §3.2.A, D16), with her
/// consent: the server creates her account in the agent's region and gives
/// her a login and a code. Needs the network. Pops with her [Beneficiary].
class RegisterBeneficiaryScreen extends StatefulWidget {
  const RegisterBeneficiaryScreen({super.key});

  @override
  State<RegisterBeneficiaryScreen> createState() => _RegisterBeneficiaryScreenState();
}

class _RegisterBeneficiaryScreenState extends State<RegisterBeneficiaryScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final error = _first.text.trim().isEmpty
        ? l10n.nameRequired
        : !RegExp(r'^\d{4,6}$').hasMatch(_pin.text)
        ? l10n.pinFormat
        : !_consent
        ? l10n.consentCheckRequired
        : null;
    if (error != null) return setState(() => _error = error);
    setState(() {
      _busy = true;
      _error = null;
    });
    final agent = AgentScope.read(context);
    try {
      final b = await agent.registerBeneficiary(
        firstName: _first.text,
        lastName: _last.text,
        pin: _pin.text,
        phone: _phone.text,
      );
      if (mounted) Navigator.of(context).pop(b);
    } on Object catch (e) {
      if (mounted) setState(() => _error = agentOnlineError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      title: l10n.agentRegisterTitle,
      bottomAction: FilledButton(
        key: const ValueKey('register-save'),
        onPressed: _busy ? null : _save,
        child: _busy
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(l10n.agentRegisterSave),
      ),
      children: [
        NoticeBox(icon: Icons.wifi, tone: Tone.info, text: l10n.agentRegisterIntro),
        const Gap(Space.l),
        if (_error != null) ...[
          NoticeBox(
            key: const ValueKey('register-error'),
            icon: Icons.error_outline,
            tone: Tone.danger,
            text: _error!,
          ),
          const Gap(Space.l),
        ],
        TextField(
          key: const ValueKey('register-first'),
          controller: _first,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.firstNameLabel),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('register-last'),
          controller: _last,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.lastNameLabel),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('register-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: l10n.phoneLabel,
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('register-pin'),
          controller: _pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: l10n.agentRegisterPin,
            helperText: l10n.agentRegisterPinHelp,
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.password),
          ),
        ),
        const Gap(Space.m),
        Card(
          child: CheckboxListTile(
            key: const ValueKey('register-consent'),
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            title: Text(l10n.agentRegisterConsent),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ],
    );
  }
}
