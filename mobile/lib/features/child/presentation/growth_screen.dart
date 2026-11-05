import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/growth/who_lms.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../agent/domain/screening.dart';
import '../data/child_repository.dart';
import '../domain/growth_display.dart';
import 'growth_chart.dart';
import 'my_children_screen.dart';

/// Growth (spec §6): weight (1 decimal), length lying before 24 months, height
/// standing after; WHO 2006 z-scores and curves when the tables are bundled.
class GrowthScreen extends StatefulWidget {
  const GrowthScreen({super.key, required this.childId});
  final String childId;

  @override
  State<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends State<GrowthScreen> {
  Future<(MyChild?, List<GrowthEntry>, WhoTables)>? _data;

  Future<(MyChild?, List<GrowthEntry>, WhoTables)> _load() async {
    final repo = childRepository(context);
    final tables = await AppScope.read(context).services.whoTables;
    return (await repo.child(widget.childId), await repo.growth(widget.childId), tables);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = AppScope.of(context).services.config.current;
    return FutureBuilder<(MyChild?, List<GrowthEntry>, WhoTables)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (child, entries, tables) = snap.data!;
        if (child == null) return const Scaffold(body: ErrorView());
        final latest = entries.isEmpty ? null : entries.last;
        final status = latest == null ? null : GrowthDisplay.status(config, latest.z);
        return AppScreen(
          title: '${l10n.growth} – ${child.name}',
          bottomAction: FilledButton.icon(
            key: const ValueKey('add-growth'),
            onPressed: () async {
              final added = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _GrowthForm(child: child, tables: tables),
              );
              if (added == true) _reload();
            },
            icon: const Icon(Icons.add),
            label: Text(l10n.addMeasure),
          ),
          children: [
            if (status != null)
              _ParentStatusPill(status: status)
            else if (entries.isNotEmpty || !tables.has(WhoIndicator.wfa))
              NoticeBox(icon: Icons.table_chart_outlined, tone: Tone.caution, text: l10n.growthStatusMissing),
            const Gap(Space.l),
            if (entries.isEmpty)
              EmptyView(icon: Icons.monitor_weight_outlined, message: l10n.noGrowth)
            else ...[
              Text(l10n.growthChartTitle, style: Theme.of(context).textTheme.titleSmall),
              const Gap(Space.s),
              GrowthChart(
                entries: entries,
                tables: tables,
                sex: child.sex,
                semanticLabel:
                    '${l10n.growthChartTitle}: ${entries.map((e) => '${formatDecimal(e.weightKg)} kg').join(', ')}',
              ),
              if (tables.has(WhoIndicator.wfa))
                Text(l10n.growthChartWho, style: Theme.of(context).textTheme.bodySmall),
              SectionTitle(l10n.childHistory),
              for (final e in entries.reversed)
                Card(
                  child: ListTile(
                    title: Text('${formatDecimal(e.weightKg)} kg · ${formatDecimal(e.lengthCm)} cm'),
                    subtitle: Text(
                      '${formatDate(e.date)} · ${e.position == 'couche' ? l10n.positionLying : l10n.positionStanding}',
                    ),
                    trailing: IconButton(
                      tooltip: l10n.delete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirmAction(
                          context,
                          message: l10n.deleteMeasure,
                          confirmLabel: l10n.delete,
                          destructive: true,
                        );
                        if (!ok || !context.mounted) return;
                        await childRepository(context).deleteGrowth(e.id);
                        _reload();
                      },
                    ),
                  ),
                ),
            ],
            const Gap(Space.l),
            Text(config.sourceLabel('croissance'), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

class _ParentStatusPill extends StatelessWidget {
  const _ParentStatusPill({required this.status});
  final ParentStatus status;

  @override
  Widget build(BuildContext context) {
    final label = localizedText(status.labels, context.lang);
    final (icon, tone) = switch (status.code) {
      'sur_la_bonne_voie' => (Icons.thumb_up_alt_outlined, Tone.success),
      'a_surveiller' => (Icons.visibility_outlined, Tone.warning),
      _ => (Icons.local_hospital_outlined, Tone.danger),
    };
    return Transform.scale(
      scale: 1.1,
      alignment: Alignment.centerLeft,
      child: StatusPill(icon: icon, label: context.l10n.growthStatus(label), tone: tone),
    );
  }
}

class _GrowthForm extends StatefulWidget {
  const _GrowthForm({required this.child, required this.tables});
  final MyChild child;
  final WhoTables tables;

  @override
  State<_GrowthForm> createState() => _GrowthFormState();
}

class _GrowthFormState extends State<_GrowthForm> {
  final _weight = TextEditingController();
  final _length = TextEditingController();
  late DateTime _date;
  String? _position;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _date = dateOnly(AppScope.read(context).services.clock.now());
  }

  @override
  void dispose() {
    _weight.dispose();
    _length.dispose();
    super.dispose();
  }

  int get _days => ScreeningCalculator.ageDays(widget.child.birthDate, _date);
  String get _pos => _position ?? ScreeningCalculator.defaultPosition(_days);

  Future<void> _save() async {
    final l10n = context.l10n;
    final weight = parseDecimal(_weight.text);
    final length = parseDecimal(_length.text);
    if (weight == null || length == null) {
      setState(() => _error = l10n.numberInvalid);
      return;
    }
    final config = AppScope.read(context).services.config.current;
    final corrected = ScreeningCalculator.correctedLength(length, _pos, _days);
    final z = GrowthMath.compute(
      widget.tables,
      sex: widget.child.sex,
      ageDays: _days,
      weightKg: weight,
      correctedLengthCm: corrected,
    );
    final outOfBounds = weight < 0.5 || weight > 50 || length < 35 || length > 140;
    if (outOfBounds || GrowthDisplay.implausible(config, z)) {
      final keep = await confirmAction(
        context,
        message:
            '${l10n.checkMeasureTitle}\n\n'
            '${l10n.checkMeasureText('${formatDecimal(weight)} kg, ${formatDecimal(length)} cm')}',
        confirmLabel: l10n.checkMeasureKeep,
      );
      if (!keep || !mounted) return;
    }
    final status = GrowthDisplay.status(config, z);
    final navigator = Navigator.of(context);
    await childRepository(context).addGrowth(
      child: widget.child,
      date: _date,
      weightKg: (weight * 10).roundToDouble() / 10,
      lengthCm: (length * 10).roundToDouble() / 10,
      position: _pos,
      tables: widget.tables,
      alerte: switch (status?.code) {
        'a_surveiller' => 'orange',
        'consulter' => 'rouge',
        _ => 'vert',
      },
    );
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = dateOnly(AppScope.of(context).services.clock.now());
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, MediaQuery.viewInsetsOf(context).bottom + Space.l),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.addMeasure, style: Theme.of(context).textTheme.titleLarge),
            const Gap(Space.m),
            if (_error != null) ...[
              NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
              const Gap(Space.m),
            ],
            DateField(
              label: l10n.measureDate,
              value: _date,
              first: widget.child.birthDate,
              last: today,
              onChanged: (d) => setState(() => _date = d),
            ),
            const Gap(Space.m),
            TextField(
              key: const ValueKey('growth-weight'),
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.weightKg,
                prefixIcon: const Icon(Icons.monitor_weight_outlined),
              ),
            ),
            const Gap(Space.m),
            TextField(
              key: const ValueKey('growth-length'),
              controller: _length,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.lengthCm, prefixIcon: const Icon(Icons.height)),
            ),
            const Gap(Space.s),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'couche', label: Text(l10n.positionLying)),
                ButtonSegment(value: 'debout', label: Text(l10n.positionStanding)),
              ],
              selected: {_pos},
              onSelectionChanged: (s) => setState(() => _position = s.first),
            ),
            const Gap(Space.l),
            FilledButton(key: const ValueKey('growth-save'), onPressed: _save, child: Text(l10n.save)),
          ],
        ),
      ),
    );
  }
}
