import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/sync/api_client.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';

enum _Scope { phone, server }

/// "Effacer toutes mes données" (loi 2014-038): "Sur ce téléphone seulement"
/// or "Aussi sur le serveur" (`/api/auth/my-data/erase/`, needs the network
/// and the PIN). The server is erased first: if it fails, nothing is erased.
class EraseDataScreen extends StatefulWidget {
  const EraseDataScreen({super.key});

  @override
  State<EraseDataScreen> createState() => _EraseDataScreenState();
}

class _EraseDataScreenState extends State<EraseDataScreen> {
  _Scope _scope = _Scope.phone;
  bool _children = false;
  bool _askPin = false;
  bool _busy = false;
  String? _error;

  Future<void> _erase({String? pin}) async {
    final l10n = context.l10n;
    final session = AppScope.read(context).session;
    final active = session.active;
    if (active == null) return;
    final navigator = Navigator.of(context);
    final sync = active.sync;
    final server = _scope == _Scope.server && sync?.account != null;
    if (server && pin == null) return setState(() => _askPin = true);
    if (!server) {
      final ok = await confirmAction(
        context,
        message: l10n.eraseAllConfirm,
        confirmLabel: l10n.erase,
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (server) {
      try {
        await sync!.eraseOnServer(pin!, includeChildren: _children);
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = e.code == 'pin_incorrect'
              ? l10n.eraseWrongPin
              : e.code == 'offline'
              ? l10n.eraseServerOffline
              : l10n.eraseServerFailed;
        });
        return;
      }
    }
    await session.deleteProfile(active.info.id);
    navigator.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sync = AppScope.of(context).session.active?.sync;
    final hasAccount = sync?.account != null;
    if (_askPin) {
      return AppScreen(
        title: l10n.eraseAll,
        children: [
          if (_error != null) ...[
            NoticeBox(
              key: const ValueKey('erase-error'),
              icon: Icons.error_outline,
              tone: Tone.danger,
              text: _error!,
            ),
            const Gap(Space.l),
          ],
          Text(
            l10n.eraseEnterPin,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const Gap(Space.l),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else
            PinPad(onCompleted: (pin) => _erase(pin: pin)),
        ],
      );
    }
    return AppScreen(
      title: l10n.eraseAll,
      bottomAction: FilledButton.icon(
        key: const ValueKey('erase-confirm'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
        onPressed: _busy ? null : _erase,
        icon: const Icon(Icons.delete_forever_outlined),
        label: Text(l10n.erase),
      ),
      children: [
        Text(l10n.eraseChoiceTitle, style: Theme.of(context).textTheme.titleMedium),
        const Gap(Space.m),
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.m),
        ],
        Card(
          child: RadioGroup<_Scope>(
            groupValue: _scope,
            onChanged: (v) => setState(() => _scope = v ?? _Scope.phone),
            child: Column(
              children: [
                RadioListTile<_Scope>(
                  key: const ValueKey('erase-phone-only'),
                  value: _Scope.phone,
                  title: Text(l10n.erasePhoneOnly),
                  subtitle: Text(l10n.erasePhoneOnlyHint),
                ),
                const Divider(),
                RadioListTile<_Scope>(
                  key: const ValueKey('erase-server-too'),
                  value: _Scope.server,
                  enabled: hasAccount,
                  title: Text(l10n.eraseServerToo),
                  subtitle: Text(hasAccount ? l10n.eraseServerTooHint : l10n.eraseNoAccount),
                ),
              ],
            ),
          ),
        ),
        if (_scope == _Scope.server && hasAccount) ...[
          const Gap(Space.m),
          Card(
            child: CheckboxListTile(
              key: const ValueKey('erase-children'),
              value: _children,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => _children = v ?? false),
              title: Text(l10n.eraseIncludeChildren),
            ),
          ),
        ],
      ],
    );
  }
}
