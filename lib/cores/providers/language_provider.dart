import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLanguage { mg, fr }

final languageProvider = NotifierProvider<LanguageNotifier, AppLanguage>(
  LanguageNotifier.new,
);

class LanguageNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() => AppLanguage.mg;

  void select(AppLanguage language) => state = language;
}
