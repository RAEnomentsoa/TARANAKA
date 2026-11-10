import 'package:flutter/material.dart';

import '../core/i18n/fallback_localizations.dart';
import '../core/i18n/l10n.dart';
import '../core/i18n/language.dart';
import '../core/platform/screen_events.dart';
import '../core/security/profile.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/states.dart';
import '../features/agent/presentation/agent_login_screen.dart';
import '../features/home/presentation/module_routes.dart';
import '../features/home/presentation/personal_home_screen.dart';
import '../features/onboarding/presentation/consent_screen.dart';
import '../features/onboarding/presentation/create_profile_screen.dart';
import '../features/onboarding/presentation/language_screen.dart';
import '../features/onboarding/presentation/profile_type_screen.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/profiles/presentation/profile_picker_screen.dart';
import 'app_scope.dart';
import 'app_services.dart';
import 'session_controller.dart';

class TaranakaApp extends StatefulWidget {
  const TaranakaApp({super.key, required this.services, required this.session});

  final AppServices services;
  final SessionController session;

  @override
  State<TaranakaApp> createState() => _TaranakaAppState();
}

class _TaranakaAppState extends State<TaranakaApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  String? _gateIdentity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_onSession);
    // Never locked after a delay of inactivity: only when the screen turns
    // off, when the user locks it herself, or when the app is closed.
    ScreenEvents.listen(widget.session.lock);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onSession);
    ScreenEvents.stop();
    super.dispose();
  }

  /// When the app locks or the profile changes, every open screen is closed so
  /// nothing of the previous profile stays reachable.
  void _onSession() {
    final s = widget.session;
    final identity = '${s.stage.name}:${s.active?.info.id}';
    if (identity != _gateIdentity) {
      final changedProfile = _gateIdentity != null;
      _gateIdentity = identity;
      if (changedProfile) _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // Back in front: lock if the screen turned off meanwhile (a switch to
      // another app, however long, never locks by itself).
      case AppLifecycleState.resumed:
        ScreenEvents.takeScreenOff().then((off) {
          if (off) widget.session.lock();
        });
      // The app is being closed completely.
      case AppLifecycleState.detached:
        widget.session.lock();
      case AppLifecycleState.inactive || AppLifecycleState.hidden || AppLifecycleState.paused:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      session: widget.session,
      child: Builder(
        builder: (context) {
          final session = AppScope.of(context).session;
          return MaterialApp(
            navigatorKey: _navigatorKey,
            onGenerateTitle: (context) => context.l10n.appName,
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: Locale(session.languageCode ?? 'mg'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [AppLocalizations.delegate, ...frameworkDelegates],
            builder: (context, child) {
              appLanguage = Localizations.localeOf(context).languageCode;
              return child!;
            },
            home: const AppGate(),
          );
        },
      ),
    );
  }
}

/// Chooses the root screen from the session stage.
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return switch (session.stage) {
      SessionStage.loading => const Scaffold(body: LoadingView()),
      SessionStage.chooseLanguage => const LanguageScreen(),
      SessionStage.welcome => const WelcomeScreen(),
      SessionStage.chooseProfileType => const ProfileTypeScreen(),
      SessionStage.consent => const ConsentScreen(),
      // "Agent de santé": straight to the account login, which creates the profile.
      SessionStage.createFirstProfile =>
        session.firstProfileMode == ProfileMode.agent
            ? AgentLoginScreen.newProfile(onCancel: session.clearFirstProfileMode)
            : CreateProfileScreen(
                presetMode: session.firstProfileMode,
                onCancel: session.clearFirstProfileMode,
              ),
      SessionStage.locked => const ProfilePickerScreen(),
      SessionStage.unlocked =>
        session.active!.info.mode == ProfileMode.agent
            ? ModuleRoutes.agentHome()
            : const PersonalHomeScreen(),
    };
  }
}
