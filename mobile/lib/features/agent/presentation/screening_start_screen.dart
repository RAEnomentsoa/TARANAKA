import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/sync/api_client.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';
import 'agent_scope.dart';
import 'beneficiary_file_screen.dart';
import 'measurement_form_screen.dart';
import 'qr_scan_screen.dart';
import 'register_beneficiary_screen.dart';

/// Message for an online action of the agent that failed.
String agentOnlineError(BuildContext context, Object e) {
  final l10n = context.l10n;
  if (e is! ApiException) return l10n.syncProblemServer;
  return switch (e.code) {
    'offline' => l10n.agentNeedsNetwork,
    'auth_expired' => l10n.syncProblemAuth,
    _ when e.status == 404 => l10n.agentCodeUnknown,
    _ => l10n.syncProblemServer,
  };
}

/// Step 1 of a screening (D16): choose the beneficiary first — scan her QR
/// code, type her code, find her in the list of the zone, or register her
/// (no phone). Then one of her children, or a new child attached to her.
class ScreeningStartScreen extends StatefulWidget {
  const ScreeningStartScreen({super.key});

  @override
  State<ScreeningStartScreen> createState() => _ScreeningStartScreenState();
}

class _ScreeningStartScreenState extends State<ScreeningStartScreen> {
  final _search = TextEditingController();
  final _code = TextEditingController();
  Future<List<Beneficiary>>? _list;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _list ??= AgentScope.read(context).repo.beneficiaries();
  }

  @override
  void dispose() {
    _search.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Reloads unless the screen was closed meanwhile (e.g. the app locked
  /// itself and closed the database).
  void _reload() {
    if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
    setState(() {
      _list = AgentScope.read(context).repo.beneficiaries(search: _search.text);
    });
  }

  Future<void> _run(Future<Beneficiary?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = await action();
      if (b != null && mounted) {
        await pushAgent<void>(context, BeneficiaryFileScreen(beneficiaryId: b.id));
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = agentOnlineError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _scan() async {
    final agent = AgentScope.read(context);
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (code == null || code.isEmpty) return;
    await _run(() => agent.openByCode(code));
  }

  Future<void> _openCode() async {
    final agent = AgentScope.read(context);
    final code = _code.text.trim();
    if (code.isEmpty) return setState(() => _error = context.l10n.agentCodeLabel);
    await _run(() => agent.openByCode(code));
  }

  Future<void> _searchZone() async {
    final agent = AgentScope.read(context);
    await _run(() async {
      await agent.searchBeneficiaries(_search.text);
      return null;
    });
  }

  /// A woman already on this phone: her file is refreshed if there is
  /// network, otherwise the one kept is shown.
  Future<void> _open(Beneficiary b) async {
    final agent = AgentScope.read(context);
    await _run(() async {
      try {
        return await agent.openBeneficiary(b.id);
      } on ApiException catch (e) {
        if (e.code == 'offline' && b.file != null) return b;
        rethrow;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.agentChooseBeneficiary)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('register-beneficiary'),
        onPressed: _busy
            ? null
            : () => pushAgent<Beneficiary>(context, const RegisterBeneficiaryScreen())
                  .then((b) {
                    if (b != null && context.mounted) {
                      return pushAgent<void>(
                        context,
                        BeneficiaryFileScreen(beneficiaryId: b.id, justRegistered: true),
                      );
                    }
                  })
                  .whenComplete(_reload),
        icon: const Icon(Icons.person_add_alt),
        label: Text(l10n.agentRegisterWoman),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Beneficiary>>(
          future: _list,
          builder: (context, snap) {
            final people = snap.data ?? const <Beneficiary>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 96),
              children: [
                if (_busy) ...[const LinearProgressIndicator(), const Gap(Space.m)],
                if (_error != null) ...[
                  NoticeBox(
                    key: const ValueKey('beneficiary-error'),
                    icon: Icons.error_outline,
                    tone: Tone.danger,
                    text: _error!,
                  ),
                  const Gap(Space.m),
                ],
                FilledButton.icon(
                  key: const ValueKey('scan-qr'),
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.agentScanQr),
                ),
                const Gap(Space.m),
                // Stacked, not side by side: room for large text at 320 dp
                // (and the theme's buttons take the full width).
                TextField(
                  key: const ValueKey('beneficiary-code'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _openCode(),
                  decoration: InputDecoration(
                    labelText: l10n.agentCodeLabel,
                    prefixIcon: const Icon(Icons.pin_outlined),
                  ),
                ),
                const Gap(Space.s),
                OutlinedButton(
                  key: const ValueKey('open-code'),
                  onPressed: _busy ? null : _openCode,
                  child: Text(l10n.agentOpen),
                ),
                SectionTitle(l10n.agentSearchZone),
                TextField(
                  key: const ValueKey('beneficiary-search'),
                  controller: _search,
                  onChanged: (_) => _reload(),
                  onSubmitted: (_) => _searchZone(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: l10n.agentSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      key: const ValueKey('search-zone'),
                      tooltip: l10n.agentSearchZone,
                      icon: const Icon(Icons.cloud_download_outlined),
                      onPressed: _busy ? null : _searchZone,
                    ),
                  ),
                ),
                const Gap(Space.m),
                if (snap.hasError)
                  ErrorView(onRetry: _reload)
                else if (!snap.hasData)
                  const LoadingView()
                else if (people.isEmpty)
                  EmptyView(icon: Icons.person_search, message: l10n.agentNoBeneficiaries)
                else
                  for (final b in people) ...[
                    Card(
                      child: ListTile(
                        key: ValueKey('beneficiary-${b.id}'),
                        leading: Icon(
                          b.pregnant ? Icons.pregnant_woman : Icons.woman,
                          color: AppColors.accent,
                          size: 32,
                        ),
                        title: Text(b.displayName.isEmpty ? (b.code ?? '') : b.displayName),
                        subtitle: SubtitleWithPills(
                          text: [
                            if (b.code != null) b.code!,
                            if (b.phone != null && b.phone!.isNotEmpty) b.phone!,
                            l10n.agentChildCount(b.childCount),
                          ].join(' · '),
                          pills: [
                            if (b.followed)
                              StatusPill(
                                icon: Icons.folder_shared_outlined,
                                label: l10n.agentFollowed,
                                tone: Tone.info,
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => _open(b),
                      ),
                    ),
                    const Gap(Space.s),
                  ],
                Text(l10n.agentNeedsNetworkHint, style: theme.bodySmall),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// New child of [mother] (D16: `mere_id` is mandatory): name, sex, birth
/// date (the age is always computed, spec §6).
class ChildFormScreen extends StatefulWidget {
  const ChildFormScreen({super.key, required this.mother, this.pregnancyId});

  final Beneficiary mother;
  final String? pregnancyId;

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
      regionId: widget.mother.regionId ?? user.regionId,
      agentId: user.id,
      motherId: widget.mother.id,
      pregnancyId: widget.pregnancyId,
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
        NoticeBox(
          icon: Icons.woman,
          tone: Tone.info,
          text: l10n.childFormMother(
            widget.mother.displayName.isEmpty ? (widget.mother.code ?? '') : widget.mother.displayName,
          ),
        ),
        const Gap(Space.l),
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
