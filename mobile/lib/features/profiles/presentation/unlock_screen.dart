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

/// "Entrez votre code secret": 5 attempts, then a delay that grows (30 s,
/// 1 min, 5 min, 15 min). The fingerprint, when enabled on this profile and
/// available on the phone, is offered at once and stays one tap away.
class _UnlockScreenState extends State<UnlockScreen> {
  String? _error;
  DateTime? _lockedUntil;
  Timer? _ticker;
  bool _busy = false;
  bool _biometric = false;

  @override
  void initState() {
    super.initState();
    final profile = _profile();
    final until = profile?.lockedUntil;
    if (until != null && DateTime.now().isBefore(until)) _startLock(until);
    if (profile?.biometric ?? false) {
      AppScope.read(context).services.biometrics.available().then((ok) {
        if (!mounted || !ok) return;
        setState(() => _biometric = true);
        _withBiometric();
      });
    }
  }

  Future<void> _withBiometric() async {
    if (_busy) return;
    final l10n = context.l10n;
    final scope = AppScope.read(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final confirmed = await scope.services.biometrics.authenticate(l10n.biometricReason);
    final opened = confirmed && await scope.session.unlockWithBiometric(widget.profileId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (opened) {
      navigator.popUntil((r) => r.isFirst);
    } else if (confirmed) {
      // The saved key is gone (e.g. data cleared): the PIN, then re-enable.
      setState(() {
        _biometric = false;
        _error = l10n.biometricUnavailable;
      });
    }
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
            // 5 attempts in all, then a delay.
            final left = PinLockoutPolicy.freeAttempts - failures + 1;
            _error = l10n.pinWrongRemaining(left);
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
        if (_biometric) ...[
          const Gap(Space.l),
          OutlinedButton.icon(
            key: const ValueKey('unlock-biometric'),
            onPressed: _busy ? null : _withBiometric,
            icon: const Icon(Icons.fingerprint, size: 28),
            label: Text(l10n.biometricUse),
          ),
        ],
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
