import 'package:flutter/material.dart';

import '../data/agent_controller.dart';

/// Gives the agent screens their controller (repository + sync).
class AgentScope extends InheritedNotifier<AgentController> {
  const AgentScope({super.key, required AgentController controller, required super.child})
    : super(notifier: controller);

  static AgentController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentScope>()!.notifier!;

  static AgentController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AgentScope>()!.notifier!;
}

/// Opens an agent screen, keeping the controller available on the new route.
Future<T?> pushAgent<T>(BuildContext context, Widget screen, {bool replace = false}) {
  final controller = AgentScope.read(context);
  final route = MaterialPageRoute<T>(
    builder: (_) => AgentScope(controller: controller, child: screen),
  );
  return replace
      ? Navigator.of(context).pushReplacement<T, void>(route)
      : Navigator.of(context).push<T>(route);
}
