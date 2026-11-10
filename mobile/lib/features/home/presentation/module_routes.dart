import 'package:flutter/widgets.dart';

import '../../agent/presentation/agent_access_screen.dart';
import '../../agent/presentation/agent_home_screen.dart';
import '../../child/presentation/my_children_screen.dart';
import '../../cycle/presentation/cycle_home_screen.dart';
import '../../pregnancy/presentation/pregnancy_home_screen.dart';

/// Entry points of the modules.
abstract final class ModuleRoutes {
  static Widget cycle() => const CycleHomeScreen();
  static Widget pregnancy() => const PregnancyHomeScreen();
  static Widget child() => const MyChildrenScreen();
  static Widget agentAccess() => const AgentAccessScreen();
  static Widget agentHome() => const AgentHomeScreen();
}
