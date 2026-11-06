import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cores/l10n/labels.dart';
import '../../cores/providers/language_provider.dart';
import '../../cores/services/cycle_timeline.dart';
import '../../cores/themes/app_colors.dart';

extension PhaseStyle on CyclePhase {
  Color get color => switch (this) {
    CyclePhase.menstruation => AppColors.menstruation,
    CyclePhase.follicular => AppColors.follicular,
    CyclePhase.ovulation => AppColors.ovulation,
    CyclePhase.luteal => AppColors.luteal,
  };

  /// Couleur du texte posé sur [color].
  Color get onColor => switch (this) {
    CyclePhase.menstruation || CyclePhase.ovulation => AppColors.white,
    CyclePhase.follicular || CyclePhase.luteal => AppColors.ink,
  };

  IconData get icon => switch (this) {
    CyclePhase.menstruation => Symbols.water_drop,
    CyclePhase.follicular => Symbols.eco,
    CyclePhase.ovulation => Symbols.egg,
    CyclePhase.luteal => Symbols.dark_mode,
  };
}

/// Légende des phases : l'icône double la couleur.
class PhaseLegend extends StatelessWidget {
  const PhaseLegend({super.key, required this.language});

  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final phase in CyclePhase.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: phase.color,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(phase.icon, size: 16, color: phase.onColor),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(language.phaseName(phase))),
            ],
          ),
      ],
    );
  }
}
