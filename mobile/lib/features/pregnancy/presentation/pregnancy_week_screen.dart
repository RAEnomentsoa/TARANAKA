import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../domain/pregnancy_weeks.dart';

/// "Ma grossesse semaine par semaine": the baby, the body and one tip for the
/// current SA, with the previous and next weeks one tap away.
class PregnancyWeekScreen extends StatefulWidget {
  const PregnancyWeekScreen({super.key, required this.currentWeek});

  /// SA of today.
  final int currentWeek;

  @override
  State<PregnancyWeekScreen> createState() => _PregnancyWeekScreenState();
}

class _PregnancyWeekScreenState extends State<PregnancyWeekScreen> {
  late int _week = widget.currentWeek.clamp(pregnancyWeekMin, pregnancyWeekMax);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final info = pregnancyWeekInfo(_week);
    final lang = context.lang;
    final isCurrent = _week == widget.currentWeek;
    return AppScreen(
      title: l10n.pregnancyWeekTitle,
      children: [
        Row(
          children: [
            IconButton.outlined(
              key: const ValueKey('week-prev'),
              tooltip: l10n.weekPrev,
              onPressed: _week > pregnancyWeekMin ? () => setState(() => _week--) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    l10n.weekValue(_week),
                    key: const ValueKey('week-value'),
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (isCurrent)
                    Text(l10n.weekThis, textAlign: TextAlign.center, style: text.bodySmall)
                  else
                    TextButton(
                      key: const ValueKey('week-current'),
                      onPressed: () => setState(() => _week = widget.currentWeek),
                      child: Text(l10n.weekBackToCurrent),
                    ),
                ],
              ),
            ),
            IconButton.outlined(
              key: const ValueKey('week-next'),
              tooltip: l10n.weekNext,
              onPressed: _week < pregnancyWeekMax ? () => setState(() => _week++) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const Gap(Space.m),
        Text(l10n.pregnancyWeekIntro(_week), style: text.bodyLarge),
        const Gap(Space.l),
        _Section(
          icon: Icons.child_care,
          title: l10n.weekBaby,
          body: info.babyIn(lang),
          sectionKey: 'week-baby',
        ),
        const Gap(Space.m),
        _Section(
          icon: Icons.pregnant_woman,
          title: l10n.weekBody,
          body: info.bodyIn(lang),
          sectionKey: 'week-body',
        ),
        const Gap(Space.m),
        _Section(
          icon: Icons.lightbulb_outline,
          title: l10n.weekTip,
          body: info.tipIn(lang),
          sectionKey: 'week-tip',
        ),
        const Gap(Space.l),
        Text(l10n.weekNote, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.body, required this.sectionKey});

  final IconData icon;
  final String title;
  final String body;
  final String sectionKey;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      key: ValueKey(sectionKey),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.accent, size: 28),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  const Gap(Space.xs),
                  Text(body, style: text.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
