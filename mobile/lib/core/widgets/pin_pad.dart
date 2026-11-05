import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/l10n.dart';
import '../theme/tokens.dart';

/// 4-digit PIN entry with large keys (no system keyboard, so it works the same
/// on every phone and never suggests or remembers the PIN).
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onCompleted, this.enabled = true, this.length = 4});

  final ValueChanged<String> onCompleted;
  final bool enabled;
  final int length;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _value = '';

  void clear() => setState(() => _value = '');

  void _tap(String digit) {
    if (!widget.enabled || _value.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _value += digit);
    if (_value.length == widget.length) {
      final pin = _value;
      // Cleared first, so the parent can show an error and ask again.
      setState(() => _value = '');
      widget.onCompleted(pin);
    }
  }

  void _delete() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          label: l10n.pinDigitsEntered(_value.length),
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                Container(
                  margin: const EdgeInsets.all(Space.s),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _value.length ? AppColors.accent : AppColors.surface,
                    border: Border.all(color: AppColors.accent, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          _row([for (final d in row) _key(d)]),
        _row([
          const SizedBox(width: Space.touchLarge + Space.l, height: Space.touchLarge),
          _key('0'),
          SizedBox(
            width: Space.touchLarge + Space.l,
            height: Space.touchLarge,
            child: IconButton(
              tooltip: l10n.pinDeleteDigit,
              onPressed: widget.enabled ? _delete : null,
              icon: const Icon(Icons.backspace_outlined, size: 28),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
  );

  Widget _key(String digit) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.s),
    child: SizedBox(
      width: Space.touchLarge + Space.s,
      height: Space.touchLarge,
      child: OutlinedButton(
        key: ValueKey('pin-$digit'),
        onPressed: widget.enabled ? () => _tap(digit) : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(Space.touchLarge, Space.touchLarge),
          padding: EdgeInsets.zero,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.accentSoftBorder),
        ),
        child: Text(digit, style: Theme.of(context).textTheme.headlineSmall),
      ),
    ),
  );
}
