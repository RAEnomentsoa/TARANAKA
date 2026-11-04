import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Visual tone of a status. Colour is never alone: a pill always has an icon
/// and a label.
enum Tone {
  neutral(AppColors.neutral, AppColors.neutralSoft),
  info(AppColors.accent, AppColors.accentSoft),
  success(AppColors.success, AppColors.successSoft),
  caution(AppColors.caution, AppColors.cautionSoft),
  warning(AppColors.warning, AppColors.warningSoft),
  danger(AppColors.danger, AppColors.dangerSoft);

  const Tone(this.foreground, this.background);
  final Color foreground;
  final Color background;
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.label, required this.tone});

  final IconData icon;
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.s + 2, vertical: Space.xs + 2),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(Radii.l),
          border: Border.all(color: tone.foreground.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: tone.foreground),
            const SizedBox(width: Space.xs + 2),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: tone.foreground, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A coloured message block: icon + text, for warnings and notices.
class NoticeBox extends StatelessWidget {
  const NoticeBox({super.key, required this.icon, required this.text, this.tone = Tone.info, this.title});

  final IconData icon;
  final String text;
  final String? title;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(Radii.m),
        border: Border.all(color: tone.foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone.foreground),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: theme.titleSmall?.copyWith(color: tone.foreground)),
                Text(text, style: theme.bodyMedium?.copyWith(color: AppColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
