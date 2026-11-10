import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import 'language_screen.dart';

/// "Bienvenue sur TARANAKA": what the app is for, before any profile choice.
/// Shown at first launch, right after the language; "Commencer" leads to
/// "Pour qui utilisez-vous l'application ?". Vector icons only, no emoji.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = AppScope.of(context).session;
    final text = Theme.of(context).textTheme;
    final pillars = [
      (Icons.calendar_today_outlined, l10n.welcomeCycleTitle, l10n.welcomeCycle),
      (Icons.pregnant_woman, l10n.welcomePregnancyTitle, l10n.welcomePregnancy),
      (Icons.child_care, l10n.welcomeChildTitle, l10n.welcomeChild),
      (Icons.health_and_safety_outlined, l10n.welcomeNutritionTitle, l10n.welcomeNutrition),
    ];
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const ValueKey('welcome-language'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => LanguageScreen(onChosen: () => Navigator.of(context).pop()),
                        ),
                      ),
                      icon: const Icon(Icons.translate),
                      label: Text(l10n.language),
                    ),
                  ),
                  Center(
                    child: Image.asset(
                      'assets/images/logo_v1.png',
                      width: 120,
                      height: 120,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const Gap(Space.l),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.welcomeTitle,
                      key: const ValueKey('welcome-title'),
                      textAlign: TextAlign.center,
                      style: text.headlineSmall?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Gap(Space.s),
                  Text(
                    l10n.welcomeTagline,
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(color: AppColors.text),
                  ),
                  const Gap(Space.xl),
                  Text(l10n.welcomeIntro, style: text.bodyLarge),
                  const Gap(Space.l),
                  for (final (icon, title, body) in pillars) ...[
                    _Pillar(icon: icon, title: title, body: body),
                    const Gap(Space.l),
                  ],
                  const Gap(Space.s),
                  Text(
                    l10n.welcomeConclusion,
                    key: const ValueKey('welcome-conclusion'),
                    textAlign: TextAlign.center,
                    style: text.titleSmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // The main action stays visible at the bottom, whatever the scroll.
      bottomNavigationBar: SafeArea(
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.l),
              child: FilledButton.icon(
                key: const ValueKey('welcome-start'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Space.touchLarge - 8)),
                onPressed: session.startFromWelcome,
                icon: const Icon(Icons.arrow_forward),
                label: Text(l10n.welcomeStart),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the four pillars: icon in a soft circle, short title, one sentence.
class _Pillar extends StatelessWidget {
  const _Pillar({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.s + 2),
            decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                const Gap(Space.xs),
                Text(body, style: text.bodyLarge?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
