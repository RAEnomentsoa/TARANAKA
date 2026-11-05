import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/security/pin_lockout.dart';
import '../../../core/security/profile.dart';
import '../../../core/security/profile_registry.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import 'forgot_pin_screen.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.profileId});

  final String profileId;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  String? _error;
  DateTime? _lockedUntil;
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final profile = _profile();
    final until = profile?.lockedUntil;
    if (until != null && DateTime.now().isBefore(until)) _startLock(until);
  }

  ProfileInfo? _profile() {
    final profiles = AppScope.read(context).session.profiles;
    for (final p in profiles) {
      if (p.id == widget.profileId) return p;
    }
    return null;
  }

  void _startLock(DateTime until) {
    _lockedUntil = until;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_lockedUntil!)) {
        t.cancel();
        setState(() {
          _lockedUntil = null;
          _error = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _submit(String pin) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final result = await AppScope.read(context).session.unlock(widget.profileId, pin);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Unlocked():
        navigator.popUntil((r) => r.isFirst);
      case WrongPin(:final failures, :final lockedUntil):
        setState(() {
          if (lockedUntil != null) {
            _startLock(lockedUntil);
            _error = null;
          } else {
            final left = PinLockoutPolicy.freeAttempts - failures + 1;
            _error = left <= 2 ? l10n.pinWrongRemaining(left) : l10n.pinWrong;
          }
        });
      case LockedOut(:final until):
        setState(() => _startLock(until));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = _profile();
    if (profile == null) return const Scaffold(body: LoadingView());
    final locked = _lockedUntil != null;
    return AppScreen(
      title: profile.displayName,
      children: [
        Text(l10n.enterPin, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const Gap(Space.l),
        if (locked)
          NoticeBox(
            icon: Icons.timer_outlined,
            tone: Tone.warning,
            text: l10n.pinLockedUntil(formatWait(context, _lockedUntil!.difference(DateTime.now()))),
          )
        else if (_error != null)
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
        const Gap(Space.m),
        PinPad(enabled: !locked && !_busy, onCompleted: _submit),
        const Gap(Space.l),
        TextButton(
          key: const ValueKey('forgot-pin'),
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => ForgotPinScreen(profileId: profile.id))),
          child: Text(l10n.forgotPin),
        ),
      ],
    );
  }
}
