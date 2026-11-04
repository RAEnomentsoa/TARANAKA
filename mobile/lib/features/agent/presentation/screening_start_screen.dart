import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';
import '../domain/screening.dart';
import 'agent_child_screen.dart';
import 'agent_scope.dart';
import 'measurement_form_screen.dart';

/// Step 1 of a screening: find the child, or add a new one.
class ScreeningStartScreen extends StatefulWidget {
  const ScreeningStartScreen({super.key});

  @override
  State<ScreeningStartScreen> createState() => _ScreeningStartScreenState();
}

class _ScreeningStartScreenState extends State<ScreeningStartScreen> {
  final _search = TextEditingController();
  Future<List<Child>>? _children;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _children ??= AgentScope.read(context).repo.children();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Reloads unless the screen was closed meanwhile (e.g. the app locked
  /// itself and closed the database).
  void _reload() {
    if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
    setState(() {
      _children = AgentScope.read(context).repo.children(search: _search.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = AppScope.of(context).services.clock.now();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.agentScreen)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('new-child'),
        onPressed: () => pushAgent<void>(context, const ChildFormScreen()),
        icon: const Icon(Icons.person_add_alt),
        label: Text(l10n.newChild),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: TextField(
                key: const ValueKey('child-search'),
                controller: _search,
                onChanged: (_) => _reload(),
                decoration: InputDecoration(
                  labelText: l10n.searchChild,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Child>>(
                future: _children,
                builder: (context, snap) {
                  if (snap.hasError) return ErrorView(onRetry: _reload);
                  if (!snap.hasData) return const LoadingView();
                  final children = snap.data!;
                  if (children.isEmpty) {
                    return EmptyView(icon: Icons.child_care, message: l10n.noChildren);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 96),
                    itemCount: children.length,
                    separatorBuilder: (_, _) => const Gap(Space.s),
                    itemBuilder: (context, i) {
                      final c = children[i];
                      final months = ScreeningCalculator.ageMonths(
                        ScreeningCalculator.ageDays(c.birthDate, today),
                      );
                      return Card(
                        child: ListTile(
                          key: ValueKey('child-${c.id}'),
                          leading: Icon(
                            c.sex == 'F' ? Icons.girl : Icons.boy,
                            color: AppColors.accent,
                            size: 32,
                          ),
                          title: Text(c.name),
                          subtitle: Text(
                            '${c.sex == 'F' ? l10n.sexF : l10n.sexM} · ${l10n.ageMonths(months)}',
                          ),
                          trailing: SyncStatusPill(c.syncStatus),
                          onTap: () => pushAgent<void>(
                            context,
                            AgentChildScreen(childId: c.id),
                          ).then((_) => _reload()),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// New child: name, sex, birth date (the age is always computed, spec §6).
class ChildFormScreen extends StatefulWidget {
  const ChildFormScreen({super.key});

  @override
  State<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends State<ChildFormScreen> {
  final _name = TextEditingController();
  String? _sex;
  DateTime? _birth;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final error = _name.text.trim().isEmpty
        ? l10n.nameRequired
        : _sex == null
        ? l10n.sexRequired
        : _birth == null
        ? l10n.birthDateRequired
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _busy = true);
    final agent = AgentScope.read(context);
    final user = agent.account!.user;
    final child = await agent.repo.createChild(
      name: _name.text,
      sex: _sex!,
      birthDate: _birth!,
      regionId: user.regionId,
      agentId: user.id,
    );
    await agent.refreshCounts();
    if (!mounted) return;
    await pushAgent<void>(context, MeasurementFormScreen(childId: child.id), replace: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = AppScope.of(context).services.clock.now();
    return AppScreen(
      title: l10n.newChild,
      bottomAction: FilledButton(
        key: const ValueKey('child-save'),
        onPressed: _busy ? null : _save,
        child: Text(l10n.continueLabel),
      ),
      children: [
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.l),
        ],
        TextField(
          key: const ValueKey('child-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.childName),
        ),
        const Gap(Space.l),
        Text(l10n.childSex, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.s),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: [
            ButtonSegment(
              value: 'F',
              icon: const Icon(Icons.girl),
              label: Text(l10n.sexF, key: const ValueKey('sex-F')),
            ),
            ButtonSegment(
              value: 'M',
              icon: const Icon(Icons.boy),
              label: Text(l10n.sexM, key: const ValueKey('sex-M')),
            ),
          ],
          selected: {?_sex},
          onSelectionChanged: (s) => setState(() => _sex = s.isEmpty ? null : s.first),
        ),
        const Gap(Space.l),
        DateField(
          key: const ValueKey('child-birth'),
          label: l10n.birthDate,
          value: _birth,
          first: DateTime(today.year - 6),
          last: today,
          onChanged: (d) => setState(() => _birth = d),
        ),
      ],
    );
  }
}

String syncLabel(BuildContext context, SyncStatus s) => switch (s) {
  SyncStatus.saved => context.l10n.syncSaved,
  SyncStatus.pending => context.l10n.syncPending,
  SyncStatus.synced => context.l10n.syncSynced,
  SyncStatus.conflict => context.l10n.syncConflict,
};
