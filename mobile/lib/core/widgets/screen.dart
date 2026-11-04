import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Standard page: scrollable (text at 200 % never gets cut), centred and
/// capped on wide screens, with an optional single main action at the bottom.
class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    this.title,
    required this.children,
    this.actions,
    this.bottomAction,
    this.padding = const EdgeInsets.all(Space.l),
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  final String? title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? bottomAction;
  final EdgeInsets padding;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title == null && actions == null && leading == null
          ? null
          : AppBar(
              title: title == null ? null : Text(title!),
              actions: actions,
              leading: leading,
              automaticallyImplyLeading: automaticallyImplyLeading,
            ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
            child: ListView(padding: padding, children: children),
          ),
        ),
      ),
      bottomNavigationBar: bottomAction == null
          ? null
          : SafeArea(
              child: Align(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.l),
                    child: bottomAction,
                  ),
                ),
              ),
            ),
    );
  }
}

class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.l, bottom: Space.s),
        child: Semantics(
          header: true,
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      );
}
