import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/growth/who_lms.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/sync/api_client.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../child/data/child_repository.dart';
import '../../child/presentation/growth_chart.dart';
import '../domain/models.dart';
import '../domain/screening.dart';
import 'agent_child_screen.dart';
import 'agent_labels.dart';
import 'agent_scope.dart';
import 'measurement_form_screen.dart';
import 'pregnancy_referral_screen.dart';
import 'screening_start_screen.dart';

class _ChildFile {
  const _ChildFile(this.child, this.measures, this.vaccines);
  final Child child;
  final List<Measurement> measures;
  final Map<String, DateTime> vaccines;
}

class _FileData {
  const _FileData({
    required this.who,
    required this.pregnancy,
    required this.dangers,
    required this.contacts,
    required this.pregnancyReferrals,
    required this.children,
  });

  final Beneficiary who;
  final AgentPregnancy? pregnancy;
  final List<(String, DateTime)> dangers;
  final int contacts;
  final List<Referral> pregnancyReferrals;
  final List<_ChildFile> children;
}

/// The file of a beneficiary in the agent app (D16): pregnancy (due date,
/// ANC, danger signs, referrals), children (growth curve, vaccines), from
/// the data received when the file was opened and at each sync. Works
/// offline; "Actualiser" downloads it again.
class BeneficiaryFileScreen extends StatefulWidget {
  const BeneficiaryFileScreen({super.key, required this.beneficiaryId, this.justRegistered = false});

  final String beneficiaryId;

  /// Just registered by the agent: her login and code are shown first, to
  /// be given to her.
  final bool justRegistered;

  @override
  State<BeneficiaryFileScreen> createState() => _BeneficiaryFileScreenState();
}

class _BeneficiaryFileScreenState extends State<BeneficiaryFileScreen> {
  Future<_FileData?>? _data;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<_FileData?> _load() async {
    final repo = AgentScope.read(context).repo;
    final who = await repo.beneficiary(widget.beneficiaryId);
    if (who == null) return null;
    final pregnancies = await repo.pregnanciesOf(who.id);
    final current = pregnancies.where((p) => p.ongoing).firstOrNull ?? pregnancies.firstOrNull;
    return _FileData(
      who: who,
      pregnancy: current,
      dangers: current == null ? const [] : await repo.dangersOf(current.id),
      contacts: current == null ? 0 : await repo.antenatalContactsOf(current.id),
      pregnancyReferrals: current == null ? const [] : await repo.referralsOfPregnancy(current.id),
      children: [
        for (final c in await repo.childrenOf(who.id))
          _ChildFile(c, await repo.measurements(c.id), await repo.vaccinesOf(c.id)),
      ],
    );
  }

  void _reload() {
    if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
    final next = _load();
    setState(() {
      _data = next;
    });
  }

  Future<void> _refresh() async {
    final agent = AgentScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await agent.openBeneficiary(widget.beneficiaryId);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = agentOnlineError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<_FileData?>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: ErrorView(onRetry: _reload));
        if (snap.connectionState != ConnectionState.done) return const Scaffold(body: LoadingView());
        final data = snap.data;
        if (data == null) return const Scaffold(body: ErrorView());
        final who = data.who;
        final name = who.displayName.isEmpty ? (who.code ?? '') : who.displayName;
        return AppScreen(
          title: l10n.fileTitle(name),
          actions: [
            IconButton(
              key: const ValueKey('file-refresh'),
              tooltip: l10n.fileRefresh,
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
          children: [
            if (_busy) ...[const LinearProgressIndicator(), const Gap(Space.m)],
            if (_error != null) ...[
              NoticeBox(icon: Icons.wifi_off, tone: Tone.warning, text: _error!),
              const Gap(Space.m),
            ],
            if (widget.justRegistered) ...[
              NoticeBox(
                key: const ValueKey('registered-notice'),
                icon: Icons.badge_outlined,
                tone: Tone.success,
                text: l10n.agentRegisterDone(who.identifiant ?? '', who.code ?? ''),
              ),
              const Gap(Space.m),
            ],
            _Identity(who: who),
            SectionTitle(l10n.filePregnancy),
            _PregnancyCard(data: data, onChanged: _reload),
            SectionTitle(l10n.fileChildren),
            if (data.children.isEmpty)
              Text(l10n.fileNoChildren)
            else
              for (final c in data.children) ...[_ChildCard(file: c, onChanged: _reload), const Gap(Space.m)],
            const Gap(Space.s),
            OutlinedButton.icon(
              key: const ValueKey('file-add-child'),
              onPressed: () => pushAgent<void>(
                context,
                ChildFormScreen(mother: who, pregnancyId: data.pregnancy?.id),
              ).then((_) => _reload()),
              icon: const Icon(Icons.person_add_alt),
              label: Text(l10n.fileAddChild),
            ),
            if (who.file != null) ...[SectionTitle(l10n.fileOther), _OtherData(file: who.file!)],
            const Gap(Space.l),
            if (who.fileAt != null)
              Text(
                l10n.fileUpdated(formatDateTime(who.fileAt!.toLocal())),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        );
      },
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.who});
  final Beneficiary who;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = [
      if (who.identifiant != null && who.identifiant!.isNotEmpty)
        (Icons.person_outline, l10n.myCodeIdentifier, who.identifiant!),
      if (who.code != null) (Icons.pin_outlined, l10n.myCodeCode, who.code!),
      if (who.phone != null && who.phone!.isNotEmpty) (Icons.phone_outlined, l10n.phoneLabel, who.phone!),
    ];
    return Card(
      child: Column(
        children: [
          for (final (icon, label, value) in rows)
            ListTile(
              leading: Icon(icon, color: AppColors.accent),
              title: Text(value),
              subtitle: Text(label),
            ),
        ],
      ),
    );
  }
}

class _PregnancyCard extends StatelessWidget {
  const _PregnancyCard({required this.data, required this.onChanged});
  final _FileData data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = data.pregnancy;
    final config = AppScope.of(context).services.config.current;
    final lang = context.lang;
    final labels = {
      for (final s in asMapList(config.signesDanger['grossesse'])) s['code']: localizedText(s, lang),
    };
    final ongoing = p != null && p.ongoing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!ongoing)
              Text(l10n.fileNoPregnancy)
            else ...[
              Row(
                children: [
                  const Icon(Icons.pregnant_woman, color: AppColors.accent),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: Text(
                      p.dueDate == null ? l10n.filePregnancy : l10n.fileDue(formatDate(p.dueDate!)),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  SyncStatusPill(p.syncStatus),
                ],
              ),
              const Gap(Space.s),
              Text(l10n.fileContacts(data.contacts)),
              if (data.dangers.isNotEmpty) ...[
                const Gap(Space.s),
                Text(l10n.fileDangers, style: Theme.of(context).textTheme.titleSmall),
                for (final (code, at) in data.dangers)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: AppColors.danger, size: 20),
                        const SizedBox(width: Space.s),
                        Expanded(child: Text('${labels[code] ?? code} · ${formatDate(at.toLocal())}')),
                      ],
                    ),
                  ),
              ],
              for (final r in data.pregnancyReferrals) ...[
                const Gap(Space.s),
                LabelWithPill(label: Text('${l10n.referralCode}: ${r.code}'), pill: ReferralStatusPill(r)),
              ],
            ],
            const Gap(Space.m),
            FilledButton.tonalIcon(
              key: const ValueKey('file-refer-pregnancy'),
              onPressed: () => pushAgent<void>(
                context,
                PregnancyReferralScreen(mother: data.who, pregnancy: ongoing ? p : null),
              ).then((_) => onChanged()),
              icon: const Icon(Icons.assignment_late_outlined),
              label: Text(l10n.fileReferPregnancy),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.file, required this.onChanged});
  final _ChildFile file;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = file.child;
    final today = AppScope.of(context).services.clock.now();
    final months = ScreeningCalculator.ageMonths(ScreeningCalculator.ageDays(c.birthDate, today));
    final tables = AgentScope.of(context).tables;
    final entries = [
      for (final m in file.measures.reversed)
        GrowthEntry(
          id: m.id,
          date: m.date,
          ageDays: ScreeningCalculator.ageDays(c.birthDate, m.date),
          weightKg: m.weightKg,
          lengthCm: m.lengthCm,
          position: m.position,
          correctedLengthCm: m.lengthCm,
          z: ZScores(waz: m.waz, haz: m.haz, whz: m.whz),
        ),
    ];
    final last = file.measures.firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              key: ValueKey('file-child-${c.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(c.sex == 'F' ? Icons.girl : Icons.boy, color: AppColors.accent, size: 32),
              title: Text(c.name),
              subtitle: SubtitleWithPills(
                text: [
                  '${c.sex == 'F' ? l10n.sexF : l10n.sexM} · ${l10n.ageMonths(months)}',
                  if (last != null) l10n.fileLastMeasure(formatDate(last.date)),
                  l10n.fileVaccines(file.vaccines.length),
                ].join('\n'),
                pills: [
                  if (last != null) ClassificationPill(last.classification),
                  SyncStatusPill(c.syncStatus),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pushAgent<void>(context, AgentChildScreen(childId: c.id)).then((_) => onChanged()),
            ),
            if (entries.isNotEmpty && !identical(tables, WhoTables.empty))
              GrowthChart(entries: entries, tables: tables, sex: c.sex, semanticLabel: l10n.fileGrowth),
            const Gap(Space.s),
            FilledButton.icon(
              key: ValueKey('file-screen-${c.id}'),
              onPressed: () =>
                  pushAgent<void>(context, MeasurementFormScreen(childId: c.id)).then((_) => onChanged()),
              icon: const Icon(Icons.straighten),
              label: Text(l10n.fileScreenChild),
            ),
          ],
        ),
      ),
    );
  }
}

/// What is only in the file read online: diet, movements, feeds, cycle.
class _OtherData extends StatelessWidget {
  const _OtherData({required this.file});
  final Map<String, Object?> file;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    int n(String key) => (file[key] as List?)?.length ?? 0;
    final shares = (file['beneficiaire'] as Map?)?['partage_cycle'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fileOtherCounts(n('alimentations'), n('mouvements_evenements'), n('tetees'))),
            const Gap(Space.xs),
            Text(shares ? l10n.fileCycleShared(n('cycles')) : l10n.fileCycleNotShared),
          ],
        ),
      ),
    );
  }
}
