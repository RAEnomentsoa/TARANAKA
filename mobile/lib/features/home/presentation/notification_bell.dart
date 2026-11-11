import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import 'reminders.dart';

/// Ids of the reminders already seen, kept in the profile database.
const _seenKey = 'notifications_seen';

/// The bell of the home header, first (before Settings and the padlock): a red
/// badge counts the reminders not seen yet; opening the list marks them seen.
/// The only place the reminders are shown (not spread on the home).
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  List<ReminderItem> _items = const [];
  Set<String> _seen = const {};

  int get _unread => _items.where((i) => !_seen.contains(i.id)).length;

  @override
  void initState() {
    super.initState();
    remindersRevision.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load(syncPhone: true);
  }

  @override
  void dispose() {
    remindersRevision.removeListener(_load);
    super.dispose();
  }

  /// [syncPhone]: when the home opens, also sets the vaccine reminders of
  /// the phone (notifications whose lock-screen text says nothing about
  /// health).
  Future<void> _load({bool syncPhone = false}) async {
    if (!mounted) return;
    final db = AppScope.read(context).session.active?.db;
    if (db == null) return;
    final items = await loadReminders(context, syncPhone: syncPhone);
    final seen = ((await db.getMetaJson(_seenKey))?['ids'] as List?)?.cast<String>().toSet() ?? <String>{};
    if (mounted) {
      setState(() {
        _items = items;
        _seen = seen;
      });
    }
  }

  Future<void> _open() async {
    final db = AppScope.read(context).session.active!.db;
    final navigator = Navigator.of(context);
    // Only the current ids are kept: a reminder that comes back later (a new
    // date, another late vaccine) has a new id and counts again.
    final ids = {for (final i in _items) i.id};
    setState(() => _seen = ids);
    await db.setMetaJson(_seenKey, {'ids': ids.toList()});
    await navigator.push(MaterialPageRoute<void>(builder: (_) => NotificationsScreen(items: _items)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unread = _unread;
    return IconButton(
      key: const ValueKey('open-notifications'),
      tooltip: unread > 0 ? l10n.notificationsUnread(unread) : l10n.notificationsTitle,
      onPressed: _open,
      icon: Badge(
        key: const ValueKey('notifications-badge'),
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(unread > 0 ? Icons.notifications_active_outlined : Icons.notifications_none),
      ),
    );
  }
}

/// The reminders of the bell, newest computation first; works offline.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.items});

  final List<ReminderItem> items;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScreen(
      title: l10n.notificationsTitle,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            child: Text(
              l10n.notificationsEmpty,
              key: const ValueKey('notifications-empty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          )
        else
          for (final i in items) ...[
            NoticeBox(icon: Icons.notifications_none, text: i.text),
            const Gap(Space.s),
          ],
      ],
    );
  }
}
