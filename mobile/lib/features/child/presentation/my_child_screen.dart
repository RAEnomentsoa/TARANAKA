import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/danger_signs_screen.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/big_tile.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../agent/domain/screening.dart';
import '../data/child_repository.dart';
import '../domain/feeding.dart';
import '../domain/vaccines.dart';
import 'feeding_screen.dart';
import 'growth_screen.dart';
import 'my_children_screen.dart';
import 'vaccines_screen.dart';

class MyChildScreen extends StatefulWidget {
  const MyChildScreen({super.key, required this.childId});
  final String childId;

  @override
  State<MyChildScreen> createState() => _MyChildScreenState();
}

class _MyChildScreenState extends State<MyChildScreen> {
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

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
    setState(() {
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final today = scope.services.clock.now();
    return FutureBuilder<(MyChild?, Map<String, DateTime>)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (child, done) = snap.data!;
        if (child == null) return const Scaffold(body: ErrorView());
        final days = ScreeningCalculator.ageDays(child.birthDate, today);
        final months = ScreeningCalculator.ageMonths(days);
        final rules = FeedingRules(config);
        final late = VaccineSchedule.build(
          config,
          birthDate: child.birthDate,
          done: done,
          today: today,
        ).where((d) => d.status == DoseStatus.late).length;
        final breastfeedingAge = months <= rules.exclusiveMaxMonths;
        return AppScreen(
          title: child.name,
          children: [
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                StatusPill(
                  icon: child.sex == 'F' ? Icons.girl : Icons.boy,
                  label:
                      '${child.sex == 'F' ? l10n.sexF : l10n.sexM} · '
                      '${months == 0 ? l10n.childAgeDays(days) : l10n.childAge(months)}',
                  tone: Tone.info,
                ),
                StatusPill(icon: Icons.cake_outlined, label: formatDate(child.birthDate), tone: Tone.neutral),
              ],
            ),
            const Gap(Space.l),
            BigTile(
              key: const ValueKey('child-growth'),
              icon: Icons.show_chart,
              title: l10n.growth,
              onTap: () => _open(GrowthScreen(childId: child.id)),
            ),
            const Gap(Space.m),
            BigTile(
              key: const ValueKey('child-feeding'),
              icon: breastfeedingAge ? Icons.child_friendly : Icons.rice_bowl_outlined,
              title: breastfeedingAge ? l10n.breastfeeding : l10n.feeding,
              onTap: () => _open(FeedingScreen(childId: child.id)),
            ),
            const Gap(Space.m),
            BigTile(
              key: const ValueKey('child-vaccines'),
              icon: Icons.vaccines_outlined,
              title: l10n.vaccines,
              subtitle: late > 0 ? l10n.vaccinesLate(late) : l10n.vaccinesUpToDate,
              trailing: late > 0
                  ? const Icon(Icons.error, color: AppColors.warning)
                  : const Icon(Icons.check_circle, color: AppColors.success),
              onTap: () => _open(VaccinesScreen(childId: child.id)),
            ),
            const Gap(Space.xl),
            FilledButton.icon(
              key: const ValueKey('child-danger'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => _open(DangerSignsScreen(kind: 'enfant', title: l10n.dangerSignsChild)),
              icon: const Icon(Icons.warning_amber_rounded),
              label: Text(l10n.dangerSignsChild),
            ),
          ],
        );
      },
    );
  }
}
