import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/pin_crypto.dart';
import '../../../core/security/profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../../account/presentation/region_field.dart';
import '../../agent/presentation/agent_login_screen.dart';
import '../../profiles/presentation/security_question_form.dart';

enum _Step { name, secret, pin, confirm, mode }

/// Profile creation (spec §3): the profile type first ("Pour moi et ma
/// famille" or "Agent de santé", unless already chosen), then name and
/// optional e-mail address (account recovery by e-mail, Firebase Auth), then
/// the secret question (recovery without Internet; personal profiles only:
/// agents go through their supervisor), then the secret 4-digit code. The
/// profile is created once the code is confirmed.
///
/// Only a verifier of the answer and the key wrapped by it are kept, on the
/// phone (see ProfileRegistry): the answer is never stored nor sent.
///
/// The actions sit at the end of the scrollable content, not in a fixed bar:
/// on small phones, with large text or with the keyboard open, the "Créer le
/// profil" button can always be scrolled to.
class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key, this.presetMode, this.canCancel = false, this.onCancel});

  final ProfileMode? presetMode;

  /// Opened as a page that can be closed (add a profile).
  final bool canCancel;

  /// First launch: back from the first step returns to the profile type.
  final VoidCallback? onCancel;

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  /// Personal profiles: her region (D16), so the account can be created and
  /// the health staff of her zone can follow her.
  String? _region;
  final _pinKey = GlobalKey<PinPadState>();
  final _secretKey = GlobalKey<SecurityQuestionFormState>();

  /// Kept when going back to the question from the PIN.
  ({String question, String answer})? _secret;
  late _Step _step = _firstStep;
  String? _pin;
  ProfileMode? _mode;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.presetMode;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// "Ajouter un profil" always starts with the profile type.
  _Step get _firstStep => widget.presetMode == null ? _Step.mode : _Step.name;

  void _cancel() {
    if (widget.canCancel) {
      Navigator.of(context).pop();
    } else {
      widget.onCancel?.call();
    }
  }

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  void _back() {
    switch (_step) {
      case _Step.mode:
        _cancel();
      case _Step.name:
        _firstStep == _Step.mode ? _go(_Step.mode) : _cancel();
      case _Step.secret:
        _go(_Step.name);
      case _Step.pin:
        _go(_needsSecret ? _Step.secret : _Step.name);
      case _Step.confirm:
        _go(_Step.pin);
    }
  }

  /// Personal profiles: the secret question is the recovery that works
  /// offline. Agents get a new PIN from their supervisor.
  bool get _needsSecret => _mode != ProfileMode.agent;

  /// Question and answer typed once: straight to the secret code.
  void _secretDone() {
    final secret = _secretKey.currentState!.validate();
    if (secret != null) {
      _secret = secret;
      _go(_Step.pin);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    final session = AppScope.read(context).session;
    final navigator = Navigator.of(context);
    await session.createProfile(
      displayName: _name.text,
      pin: _pin!,
      mode: _mode!,
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      recoveryQuestion: _secret?.question,
      recoveryAnswer: _secret?.answer,
      region: _mode == ProfileMode.personal ? _region : null,
      phone: _mode == ProfileMode.personal && _phone.text.trim().isNotEmpty ? _phone.text.trim() : null,
    );
    // The gate now shows the home of the new profile.
    if (widget.canCancel && navigator.mounted) navigator.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final atStart = _step == _firstStep;
    final canGoBack = !atStart || widget.canCancel || widget.onCancel != null;
    return PopScope(
      canPop: atStart && widget.canCancel,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AppScreen(
        title: l10n.createProfileTitle,
        automaticallyImplyLeading: false,
        leading: canGoBack
            ? IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: _back)
            : null,
        children: [
          if (_error != null) ...[
            NoticeBox(icon: Icons.error_outline, text: _error!, tone: Tone.danger),
            const Gap(Space.l),
          ],
          ..._body(context),
          ..._actions(context),
        ],
      ),
    );
  }

  /// The step's buttons, placed under its content (see the class comment).
  List<Widget> _actions(BuildContext context) {
    final l10n = context.l10n;
    final action = switch (_step) {
      _Step.name => FilledButton(
        key: const ValueKey('name-continue'),
        onPressed: () {
          final email = _email.text.trim();
          if (_name.text.trim().isEmpty) {
            setState(() => _error = l10n.nameRequired);
          } else if (email.isNotEmpty && !PinCrypto.isValidEmail(email)) {
            setState(() => _error = l10n.emailInvalid);
          } else if (_mode != ProfileMode.agent && _region == null) {
            setState(() => _error = l10n.regionRequired);
          } else {
            _go(_needsSecret ? _Step.secret : _Step.pin);
          }
        },
        child: Text(l10n.continueLabel),
      ),
      _Step.secret => FilledButton(
        key: const ValueKey('secret-continue'),
        onPressed: _secretDone,
        child: Text(l10n.continueLabel),
      ),
      _ => null,
    };
    if (action == null) return const [];
    return [
      const Gap(Space.xl),
      action,
      // The secret question is optional: skip it, straight to the code.
      if (_step == _Step.secret) ...[
        const Gap(Space.s),
        TextButton(
          key: const ValueKey('secret-skip'),
          onPressed: () {
            _secret = null;
            _go(_Step.pin);
          },
          child: Text(l10n.skip),
        ),
      ],
      const Gap(Space.l),
    ];
  }

  List<Widget> _body(BuildContext context) {
    final l10n = context.l10n;
    final title = Theme.of(context).textTheme.titleLarge;
    switch (_step) {
      case _Step.name:
        return [
          TextField(
            key: const ValueKey('profile-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: l10n.nameLabel,
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          // Optional: the profile works without it; it will allow the account
          // recovery by e-mail.
          if (_mode != ProfileMode.agent) ...[
            const Gap(Space.s),
            TextField(
              key: const ValueKey('profile-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l10n.emailLabel,
                prefixIcon: const Icon(Icons.alternate_email),
              ),
            ),
            const Gap(Space.s),
            RegionField(value: _region, onChanged: (r) => setState(() => _region = r)),
            const Gap(Space.l),
            TextField(
              key: const ValueKey('profile-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: l10n.phoneLabel,
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ];
      case _Step.secret:
        return [
          Text(l10n.secretQuestionTitle, style: title),
          const Gap(Space.s),
          Text(l10n.secretQuestionIntro),
          const Gap(Space.l),
          SecurityQuestionForm(
            key: _secretKey,
            initial: _secret,
            showAnswerHelp: false,
            onSubmitted: _secretDone,
          ),
        ];
      case _Step.pin:
        return [
          Text(l10n.pinChoose, style: title, textAlign: TextAlign.center),
          const Gap(Space.l),
          PinPad(
            key: _pinKey,
            onCompleted: (pin) {
              _pin = pin;
              _go(_Step.confirm);
            },
          ),
        ];
      case _Step.confirm:
        return [
          Text(l10n.pinConfirm, style: title, textAlign: TextAlign.center),
          const Gap(Space.l),
          PinPad(
            key: const ValueKey('pin-confirm-pad'),
            onCompleted: (pin) {
              if (pin == _pin) {
                _create();
              } else {
                _pin = null;
                setState(() {
                  _step = _Step.pin;
                  _error = l10n.pinMismatch;
                });
              }
            },
          ),
        ];
      case _Step.mode:
        return [
          Text(l10n.modeTitle, style: title),
          const Gap(Space.l),
          BigTile(
            key: const ValueKey('mode-personal'),
            icon: Icons.family_restroom,
            title: l10n.modePersonal,
            subtitle: l10n.modePersonalHint,
            onTap: () {
              _mode = ProfileMode.personal;
              _go(_Step.name);
            },
          ),
          const Gap(Space.m),
          BigTile(
            key: const ValueKey('mode-agent'),
            icon: Icons.medical_services_outlined,
            title: l10n.profileAgentBadge,
            subtitle: l10n.modeAgentHint,
            // No name nor PIN here: the account login creates the agent profile.
            onTap: () => Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute<void>(builder: (_) => const AgentLoginScreen.newProfile())),
          ),
        ];
    }
  }
}
