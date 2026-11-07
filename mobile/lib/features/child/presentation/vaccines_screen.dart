import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/child_repository.dart';
import '../domain/vaccines.dart';
import 'my_children_screen.dart';

/// Immunisation (spec §6): national PEV schedule from the configuration,
/// "fait / en retard" for each dose.
class VaccinesScreen extends StatefulWidget {
  const VaccinesScreen({super.key, required this.childId});
  final String childId;

  @override
  State<VaccinesScreen> createState() => _VaccinesScreenState();
}

class _VaccinesScreenState extends State<VaccinesScreen> {
  Future<(MyChild?, Map<String, DateTime>)>? _data;

  Future<(MyChild?, Map<String, DateTime>)> _load() async {
    final repo = childRepository(context);
    return (await repo.child(widget.childId), await repo.vaccinesDone(widget.childId));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _toggle(VaccineDose dose, MyChild child) async {
    final l10n = context.l10n;
    final repo = childRepository(context);
    if (dose.status == DoseStatus.done) {
      final ok = await confirmAction(context, message: l10n.vaccineUndo, confirmLabel: l10n.confirm);
      if (!ok) return;
      await repo.unmarkVaccine(child.id, dose.code);
    } else {
      final today = dateOnly(AppScope.read(context).services.clock.now());
      final picked = await showDateWheel(
        context,
        title: '${dose.name} – ${l10n.vaccineMarkDone}',
        initial: dose.dueDate.isAfter(today) ? today : dose.dueDate,
        first: child.birthDate,
        last: today,
      );
      if (picked == null) return;
      await repo.markVaccine(child.id, dose.code, picked);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    return FutureBuilder<(MyChild?, Map<String, DateTime>)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (child, done) = snap.data!;
        if (child == null) return const Scaffold(body: ErrorView());
        final doses = VaccineSchedule.build(
          config,
          birthDate: child.birthDate,
          done: done,
          today: scope.services.clock.now(),
        );
        String age(int days) => days == 0
            ? l10n.atBirth
            : days % 30 == 0 || days >= 180
            ? l10n.childAge((days / 30.4375).round())
            : l10n.weeksAge(days ~/ 7);
        final byAge = <int, List<VaccineDose>>{};
        for (final d in doses) {
          byAge.putIfAbsent(d.ageDays, () => []).add(d);
        }
        return AppScreen(
          title: '${l10n.vaccines} – ${child.name}',
          children: [
            Text(config.sourceLabel('calendrier_pev'), style: Theme.of(context).textTheme.bodySmall),
            for (final entry in byAge.entries) ...[
              SectionTitle(l10n.vaccineAtAge(age(entry.key))),
              for (final d in entry.value)
                Card(
                  child: ListTile(
                    key: ValueKey('vaccine-${d.code}'),
                    leading: Icon(
                      d.status == DoseStatus.done ? Icons.check_circle : Icons.vaccines_outlined,
                      color: d.status == DoseStatus.done ? AppColors.success : AppColors.accent,
                    ),
                    title: Text(d.name),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Align(alignment: Alignment.centerLeft, child: _status(context, d)),
                    ),
                    onTap: () => _toggle(d, child),
                  ),
                ),
            ],
            const Gap(Space.l),
            Text(l10n.carnetPhotoNote, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }

  Widget _status(BuildContext context, VaccineDose d) {
    final l10n = context.l10n;
    return switch (d.status) {
      DoseStatus.done => StatusPill(
        icon: Icons.check,
        label: l10n.vaccineDone(formatDate(d.doneOn!)),
        tone: Tone.success,
      ),
      DoseStatus.late => StatusPill(
        icon: Icons.error_outline,
        label: l10n.vaccineLate(formatDate(d.dueDate)),
        tone: Tone.warning,
      ),
      DoseStatus.dueToday => StatusPill(icon: Icons.today, label: l10n.vaccineDueToday, tone: Tone.info),
      DoseStatus.upcoming => StatusPill(
        icon: Icons.schedule,
        label: l10n.vaccineUpcoming(formatDate(d.dueDate)),
        tone: Tone.neutral,
      ),
    };
  }
}
