import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Large home tile: pictogram + short label (+ optional hint). Whole tile is
/// one button (≥ 64 dp high).
class BigTile extends StatelessWidget {
  const BigTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
    this.emphasis = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: emphasis ? AppColors.accent : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.l),
          side: BorderSide(color: emphasis ? AppColors.accent : AppColors.accentSoftBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.touchLarge + Space.l),
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: emphasis ? Colors.white : AppColors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 28, color: AppColors.accent),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: text.titleMedium?.copyWith(color: emphasis ? Colors.white : AppColors.text),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: Space.xs),
                          Text(
                            subtitle!,
                            style: text.bodyMedium?.copyWith(
                              color: emphasis ? Colors.white : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing ?? Icon(Icons.chevron_right, color: emphasis ? Colors.white : AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
