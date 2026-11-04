import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';

enum _Step { name, pin, confirm, mode, recovery }

/// First launch, steps 3 and 4 (spec §3): name, 4-digit PIN, mode, then an
/// optional recovery question (personal mode only: agents are reset by
/// their supervisor).
class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key, this.presetMode, this.canCancel = false});

  final ProfileMode? presetMode;
  final bool canCancel;

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _name = TextEditingController();
  final _question = TextEditingController();
  final _answer = TextEditingController();
  final _pinKey = GlobalKey<PinPadState>();
  _Step _step = _Step.name;
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
    _question.dispose();
    _answer.dispose();
    super.dispose();
  }

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  void _back() {
    switch (_step) {
      case _Step.name:
        if (widget.canCancel) Navigator.of(context).pop();
      case _Step.pin:
        _go(_Step.name);
      case _Step.confirm:
        _go(_Step.pin);
      case _Step.mode:
        _go(_Step.pin);
      case _Step.recovery:
        _go(widget.presetMode == null ? _Step.mode : _Step.pin);
    }
  }

  void _afterPin() {
    if (_mode == null) {
      _go(_Step.mode);
    } else if (_mode == ProfileMode.personal) {
      _go(_Step.recovery);
    } else {
      _create();
    }
  }

  Future<void> _create({bool withRecovery = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final session = AppScope.read(context).session;
    final navigator = Navigator.of(context);
    await session.createProfile(
      displayName: _name.text,
      pin: _pin!,
      mode: _mode!,
      recoveryQuestion: withRecovery ? _question.text : null,
      recoveryAnswer: withRecovery ? _answer.text : null,
    );
    // The gate now shows the home of the new profile.
    if (widget.canCancel && navigator.mounted) navigator.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canGoBack = _step != _Step.name || widget.canCancel;
    return PopScope(
      canPop: _step == _Step.name && widget.canCancel,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AppScreen(
        title: l10n.createProfileTitle,
        automaticallyImplyLeading: false,
        leading: canGoBack
            ? IconButton(tooltip: l10n.back, icon: const Icon(Icons.arrow_back), onPressed: _back)
            : null,
        bottomAction: switch (_step) {
          _Step.name => FilledButton(
            key: const ValueKey('name-continue'),
            onPressed: () {
              if (_name.text.trim().isEmpty) {
                setState(() => _error = l10n.nameRequired);
              } else {
                _go(_Step.pin);
              }
            },
            child: Text(l10n.continueLabel),
          ),
          _Step.recovery => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                key: const ValueKey('recovery-save'),
                onPressed: _busy
                    ? null
                    : () {
                        if (_question.text.trim().isEmpty || _answer.text.trim().isEmpty) {
                          _create();
                        } else {
                          _create(withRecovery: true);
                        }
                      },
                child: Text(l10n.save),
              ),
              const Gap(Space.s),
              TextButton(
                key: const ValueKey('recovery-skip'),
                onPressed: _busy ? null : _create,
                child: Text(l10n.skip),
              ),
            ],
          ),
          _ => null,
        },
        children: [
          if (_error != null) ...[
            NoticeBox(icon: Icons.error_outline, text: _error!, tone: Tone.danger),
            const Gap(Space.l),
          ],
          ..._body(context),
        ],
      ),
    );
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
                _afterPin();
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
              _go(_Step.recovery);
            },
          ),
          const Gap(Space.m),
          BigTile(
            key: const ValueKey('mode-agent'),
            icon: Icons.medical_services_outlined,
            title: l10n.modeAgent,
            subtitle: l10n.modeAgentHint,
            onTap: () {
              _mode = ProfileMode.agent;
              _create();
            },
          ),
        ];
      case _Step.recovery:
        return [
          Text(l10n.recoveryTitle, style: title),
          const Gap(Space.s),
          Text(l10n.recoveryHelp),
          const Gap(Space.l),
          TextField(
            key: const ValueKey('recovery-question'),
            controller: _question,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: l10n.recoveryQuestionLabel,
              hintText: l10n.recoveryQuestionHint,
            ),
          ),
          const Gap(Space.s),
          TextField(
            key: const ValueKey('recovery-answer'),
            controller: _answer,
            maxLength: 60,
            decoration: InputDecoration(labelText: l10n.recoveryAnswerLabel),
          ),
        ];
    }
  }
}
