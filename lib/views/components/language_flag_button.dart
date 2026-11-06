import 'package:flutter/material.dart';

import '../../cores/providers/language_provider.dart';
import '../../cores/themes/app_colors.dart';

/// Drapeau cliquable sélectionnant une langue. Zone tactile de 48 x 48.
class LanguageFlagButton extends StatelessWidget {
  const LanguageFlagButton({
    super.key,
    required this.language,
    required this.selected,
    required this.onPressed,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onPressed;

  String get _label => switch (language) {
    AppLanguage.mg => 'Malagasy',
    AppLanguage.fr => 'Français',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: _label,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Container(
              key: ValueKey('flag-${language.name}'),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                // L'anneau distingue la sélection sans dépendre de la couleur.
                border: Border.all(
                  color: selected ? AppColors.white : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: CustomPaint(
                  size: const Size(27, 18),
                  painter: _FlagPainter(language),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  const _FlagPainter(this.language);

  final AppLanguage language;

  @override
  void paint(Canvas canvas, Size size) {
    final third = size.width / 3;
    void fill(Rect rect, Color color) =>
        canvas.drawRect(rect, Paint()..color = color);

    switch (language) {
      case AppLanguage.mg:
        fill(Offset.zero & size, const Color(0xFFFFFFFF));
        fill(
          Rect.fromLTWH(third, 0, third * 2, size.height / 2),
          const Color(0xFFFC3D32),
        );
        fill(
          Rect.fromLTWH(third, size.height / 2, third * 2, size.height / 2),
          const Color(0xFF007E3A),
        );
      case AppLanguage.fr:
        fill(Offset.zero & size, const Color(0xFFFFFFFF));
        fill(Rect.fromLTWH(0, 0, third, size.height), const Color(0xFF000091));
        fill(
          Rect.fromLTWH(third * 2, 0, third, size.height),
          const Color(0xFFE1000F),
        );
    }
  }

  @override
  bool shouldRepaint(_FlagPainter oldDelegate) =>
      oldDelegate.language != language;
}
