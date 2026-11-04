import 'package:flutter/material.dart';

import '../i18n/l10n.dart';
import '../theme/tokens.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: context.l10n.loading,
      child: const Padding(padding: EdgeInsets.all(Space.xl), child: CircularProgressIndicator()),
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xxl, horizontal: Space.l),
    child: Column(
      children: [
        Icon(icon, size: 48, color: AppColors.accent),
        const SizedBox(height: Space.m),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
        ),
        if (action != null) ...[const SizedBox(height: Space.l), action!],
      ],
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyView(
    icon: Icons.error_outline,
    message: message ?? context.l10n.errorGeneric,
    action: onRetry == null
        ? null
        : OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.retry),
          ),
  );
}

/// Asks before an irreversible action (skill: confirmation required).
Future<bool> confirmAction(
  BuildContext context, {
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final l10n = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size(Space.touch, Space.touch),
                )
              : FilledButton.styleFrom(minimumSize: const Size(Space.touch, Space.touch)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Short duration for lockout messages ("30 s", "5 min").
String formatWait(BuildContext context, Duration d) {
  final l10n = context.l10n;
  if (d.inSeconds < 60) return l10n.durationSeconds(d.inSeconds.clamp(1, 59));
  return l10n.durationMinutes((d.inSeconds / 60).ceil());
}
