import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../../agent/domain/screening.dart';
import '../data/child_repository.dart';
import '../domain/feeding.dart';
import 'feeding_screen.dart';
import 'my_child_screen.dart';

ChildRepository childRepository(BuildContext context) {
  final scope = AppScope.read(context);
  return ChildRepository(scope.session.active!.db, clock: scope.services.clock);
}

/// "Mon enfant" (spec §6): several children per profile.
class MyChildrenScreen extends StatefulWidget {
  const MyChildrenScreen({super.key});

  @override
  State<MyChildrenScreen> createState() => _MyChildrenScreenState();
}

class _MyChildrenScreenState extends State<MyChildrenScreen> {
  Future<List<MyChild>>? _children;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _children ??= childRepository(context).children();
  }

  void _reload() {
    if (!mounted || !(ModalRoute.of(context)?.isActive ?? false)) return;
    setState(() {
      _children = childRepository(context).children();
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final today = scope.services.clock.now();
    final rules = FeedingRules(scope.services.config.current);
    return FutureBuilder<List<MyChild>>(
      future: _children,
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: ErrorView(onRetry: _reload));
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final children = snap.data!;
        return AppScreen(
          title: l10n.tileChild,
          bottomAction: OutlinedButton.icon(
            key: const ValueKey('add-my-child'),
            onPressed: () => _open(const AddMyChildScreen()),
            icon: const Icon(Icons.person_add_alt),
            label: Text(l10n.addChild),
          ),
          children: [
            if (children.isEmpty) EmptyView(icon: Icons.child_care, message: l10n.noMyChildren),
            for (final c in children) ...[
              _ChildCard(
                child: c,
                months: ScreeningCalculator.ageMonths(ScreeningCalculator.ageDays(c.birthDate, today)),
                rules: rules,
                onOpen: () => _open(MyChildScreen(childId: c.id)),
                onFeeding: () => _open(FeedingScreen(childId: c.id)),
              ),
              const Gap(Space.m),
            ],
            if (children.isNotEmpty)
              Text(l10n.personalDataLocal, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.months,
    required this.rules,
    required this.onOpen,
    required this.onFeeding,
  });

  final MyChild child;
  final int months;
  final FeedingRules rules;
  final VoidCallback onOpen;
  final VoidCallback onFeeding;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final logsMeals = months >= rules.logMinMonths && months <= rules.logMaxMonths;
    final breastfeeding = months <= rules.exclusiveMaxMonths;
    return Card(
      child: Column(
        children: [
          ListTile(
            key: ValueKey('my-child-${child.id}'),
            leading: Icon(child.sex == 'F' ? Icons.girl : Icons.boy, size: 36, color: AppColors.accent),
            title: Text(child.name, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(l10n.childAge(months)),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpen,
          ),
          if (logsMeals || breastfeeding)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
              child: FilledButton.tonalIcon(
                key: ValueKey('quick-feeding-${child.id}'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Space.touch)),
                onPressed: onFeeding,
                icon: Icon(breastfeeding ? Icons.child_friendly : Icons.rice_bowl_outlined),
                label: Text(breastfeeding ? l10n.todayBreastfeeding : l10n.todayMeals),
              ),
            ),
        ],
      ),
    );
  }
}

class AddMyChildScreen extends StatefulWidget {
  const AddMyChildScreen({super.key});

  @override
  State<AddMyChildScreen> createState() => _AddMyChildScreenState();
}

class _AddMyChildScreenState extends State<AddMyChildScreen> {
  final _name = TextEditingController();
  final _weight = TextEditingController();
  String? _sex;
  DateTime? _birth;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final weight = _weight.text.trim().isEmpty ? null : parseDecimal(_weight.text);
    final error = _name.text.trim().isEmpty
        ? l10n.nameRequired
        : _sex == null
        ? l10n.sexRequired
        : _birth == null
        ? l10n.birthDateRequired
        : (_weight.text.trim().isNotEmpty && (weight == null || weight <= 0 || weight > 7))
        ? l10n.numberInvalid
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final navigator = Navigator.of(context);
    await childRepository(context)
        .addChild(name: _name.text, sex: _sex!, birthDate: _birth!, birthWeightKg: weight);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = dateOnly(AppScope.of(context).services.clock.now());
    return AppScreen(
      title: l10n.addChild,
      bottomAction: FilledButton(
        key: const ValueKey('my-child-save'),
        onPressed: _save,
        child: Text(l10n.save),
      ),
      children: [
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.l),
        ],
        TextField(
          key: const ValueKey('my-child-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l10n.nameLabel),
        ),
        const Gap(Space.l),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          segments: [
            ButtonSegment(value: 'F', icon: const Icon(Icons.girl), label: Text(l10n.sexF)),
            ButtonSegment(value: 'M', icon: const Icon(Icons.boy), label: Text(l10n.sexM)),
          ],
          selected: {?_sex},
          onSelectionChanged: (s) => setState(() => _sex = s.isEmpty ? null : s.first),
        ),
        const Gap(Space.l),
        DateField(
          label: l10n.birthDate,
          value: _birth,
          first: DateTime(today.year - 5),
          last: today,
          onChanged: (d) => setState(() => _birth = d),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('my-child-weight'),
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.birthWeight,
            prefixIcon: const Icon(Icons.monitor_weight_outlined),
          ),
        ),
      ],
    );
  }
}
