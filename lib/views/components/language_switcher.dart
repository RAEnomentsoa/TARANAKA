import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cores/providers/language_provider.dart';
import 'language_flag_button.dart';

/// Drapeaux de choix de la langue, pour les actions de l'AppBar.
class LanguageSwitcher extends ConsumerWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in AppLanguage.values)
            LanguageFlagButton(
              language: option,
              selected: option == language,
              onPressed: () =>
                  ref.read(languageProvider.notifier).select(option),
            ),
        ],
      ),
    );
  }
}
