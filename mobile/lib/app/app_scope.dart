import 'package:flutter/widgets.dart';

import 'app_services.dart';
import 'session_controller.dart';

/// Gives every screen the services and the session.
class AppScope extends InheritedNotifier<SessionController> {
  const AppScope({
    super.key,
    required this.services,
    required SessionController session,
    required super.child,
  }) : super(notifier: session);

  final AppServices services;

  SessionController get session => notifier!;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!;
  }

  /// Without rebuilding when the session changes (for callbacks).
  static AppScope read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!;
}
