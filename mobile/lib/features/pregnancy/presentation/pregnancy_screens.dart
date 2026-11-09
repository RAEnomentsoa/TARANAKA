import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/alert_contact.dart';
import '../../../core/alerts/red_alert_screen.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/pregnancy_repository.dart';
import '../domain/pregnancy.dart';
import 'pregnancy_home_screen.dart';

// ------------------------------------------------------------------ contacts

/// Antenatal and postnatal contacts, with "J'y suis allée" (spec §5).
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.pregnancyId});
  final String pregnancyId;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  Future<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)>? _data;

  Future<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)> _load() async {
    final repo = pregnancyRepository(context);
    return (
      await repo.current(),
      await repo.contactsDone(widget.pregnancyId, 'cpn'),
      await repo.contactsDone(widget.pregnancyId, 'pn'),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _toggle(String type, CareContact c) async {
    final l10n = context.l10n;
    final repo = pregnancyRepository(context);
    if (c.status == ContactStatus.done) {
      final ok = await confirmAction(context, message: l10n.contactUndo, confirmLabel: l10n.confirm);
      if (!ok) return;
      await repo.unmarkContact(widget.pregnancyId, type, c.number);
    } else {
      final today = dateOnly(AppScope.read(context).services.clock.now());
      await repo.markContact(widget.pregnancyId, type, c.number, c.date.isAfter(today) ? today : c.date);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final calc = PregnancyCalculator(config);
    final today = scope.services.clock.now();
    return FutureBuilder<(Pregnancy?, Map<int, DateTime>, Map<int, DateTime>)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (p, anc, pnc) = snap.data!;
        if (p == null) return const Scaffold(body: ErrorView());
        Widget tile(String type, CareContact c) {
          final title = type == 'cpn'
              ? l10n.contactAnc(c.number, c.label)
              : l10n.contactPnc(c.number, c.label);
          final pill = switch (c.status) {
            ContactStatus.done => StatusPill(
              icon: Icons.check,
              label: l10n.contactDone(formatDate(c.doneOn!)),
              tone: Tone.success,
            ),
            ContactStatus.missed => StatusPill(
              icon: Icons.error_outline,
              label: l10n.contactMissed(formatDate(c.date)),
              tone: Tone.warning,
            ),
            ContactStatus.next => StatusPill(
              icon: Icons.arrow_forward,
              label: l10n.contactNext(formatDate(c.date)),
              tone: Tone.info,
            ),
            ContactStatus.upcoming => StatusPill(
              icon: Icons.schedule,
              label: l10n.contactPlanned(formatDate(c.date)),
              tone: Tone.neutral,
            ),
          };
          return Card(
            child: CheckboxListTile(
              key: ValueKey('contact-$type-${c.number}'),
              value: c.status == ContactStatus.done,
              onChanged: (_) => _toggle(type, c),
              title: Text(title),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Align(alignment: Alignment.centerLeft, child: pill),
              ),
              secondary: Tooltip(message: l10n.contactWent, child: const Icon(Icons.how_to_reg_outlined)),
            ),
          );
        }

        return AppScreen(
          title: l10n.consultations,
          children: [
            Text(l10n.contactWent, style: Theme.of(context).textTheme.bodySmall),
            if (p.delivered) ...[
              SectionTitle(l10n.postnatalTitle),
              for (final c in calc.postnatal(p.dates, pnc, today)) tile('pn', c),
              Text(config.sourceLabel('calendrier_postnatal'), style: Theme.of(context).textTheme.bodySmall),
            ],
            SectionTitle(l10n.antenatalTitle),
            for (final c in calc.antenatal(p.dates, anc, today)) tile('cpn', c),
            Text(config.sourceLabel('calendrier_cpn'), style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------- follow-up

/// Health parameters of "Mon suivi". Each one is optional; one entry is dated.
enum _Param { weight, bloodPressure, fundalHeight, hemoglobin, glucose, temperature }

/// "Mon suivi": weight, blood pressure and other measurements, each entry with
/// the date of the measurement (today by default, any past day possible).
class FollowUpScreen extends StatefulWidget {
  const FollowUpScreen({super.key, required this.pregnancyId});
  final String pregnancyId;

  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<FollowUpScreen> {
  final _fields = {for (final p in _Param.values) p: TextEditingController()};
  final _diastolic = TextEditingController();

  /// "Ce que je ressens": the search text (also a symptom of her own when
  /// nothing in the list fits) and the symptoms already chosen.
  final _notes = TextEditingController();
  final _notesFocus = FocusNode();
  final List<String> _feelings = [];
  final Set<_Param> _shown = {_Param.weight};
  DateTime? _date;
  Future<List<FollowUpEntry>>? _entries;
  String? _error;

  /// Advice shown after saving a value outside the usual limits.
  String? _advice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _date ??= dateOnly(AppScope.read(context).services.clock.now());
    _entries ??= pregnancyRepository(context).followUps(widget.pregnancyId);
  }

  @override
  void dispose() {
    for (final c in [..._fields.values, _diastolic, _notes]) {
      c.dispose();
    }
    _notesFocus.dispose();
    super.dispose();
  }

  String _label(_Param p) {
    final l10n = context.l10n;
    return switch (p) {
      _Param.weight => l10n.paramWeight,
      _Param.bloodPressure => l10n.paramBloodPressure,
      _Param.fundalHeight => l10n.paramFundalHeight,
      _Param.hemoglobin => l10n.paramHemoglobin,
      _Param.glucose => l10n.paramGlucose,
      _Param.temperature => l10n.paramTemperature,
    };
  }

  static IconData _icon(_Param p) => switch (p) {
    _Param.weight => Icons.monitor_weight_outlined,
    _Param.bloodPressure => Icons.favorite_border,
    _Param.fundalHeight => Icons.straighten,
    _Param.hemoglobin => Icons.bloodtype_outlined,
    _Param.glucose => Icons.water_drop_outlined,
    _Param.temperature => Icons.thermostat,
  };

  /// Plausible limits, to catch typing mistakes (not clinical thresholds).
  static (double, double) _range(_Param p) => switch (p) {
    _Param.weight => (25, 200),
    _Param.bloodPressure => (60, 250),
    _Param.fundalHeight => (5, 50),
    _Param.hemoglobin => (3, 20),
    _Param.glucose => (0.3, 6),
    _Param.temperature => (34, 43),
  };

  Future<void> _add() async {
    final l10n = context.l10n;
    final calc = PregnancyCalculator(AppScope.read(context).services.config.current);
    final values = <_Param, double>{};
    for (final p in _shown) {
      final text = _fields[p]!.text.trim();
      if (text.isEmpty) continue;
      final v = parseDecimal(text);
      final (lo, hi) = _range(p);
      if (v == null || v < lo || v > hi) {
        setState(() => _error = l10n.valueInvalid(_label(p)));
        return;
      }
      values[p] = v;
    }
    int? dia;
    if (_shown.contains(_Param.bloodPressure)) {
      final sysSet = values.containsKey(_Param.bloodPressure);
      final diaText = _diastolic.text.trim();
      if (sysSet != diaText.isNotEmpty) {
        setState(() => _error = l10n.valueInvalid(l10n.paramBloodPressure));
        return;
      }
      if (sysSet) {
        dia = int.tryParse(diaText);
        if (dia == null || dia < 30 || dia > 150) {
          setState(() => _error = l10n.valueInvalid(l10n.bpDiastolic));
          return;
        }
        if (dia >= values[_Param.bloodPressure]!) {
          setState(() => _error = l10n.bpOrder);
          return;
        }
      }
    }
    final sys = values[_Param.bloodPressure]?.round();
    final entry = FollowUpEntry(
      date: _date!,
      weightKg: values[_Param.weight],
      systolic: sys,
      diastolic: dia,
      fundalHeightCm: values[_Param.fundalHeight],
      hemoglobinGdl: values[_Param.hemoglobin],
      glucoseGl: values[_Param.glucose],
      temperatureC: values[_Param.temperature],
      // The chosen symptoms, then what is still typed in the field.
      notes: [..._feelings, if (_notes.text.trim().isNotEmpty) _notes.text.trim()].join(', '),
    );
    if (entry.isEmpty) {
      setState(() => _error = l10n.followUpEmpty);
      return;
    }
    final repo = pregnancyRepository(context);
    await repo.addFollowUp(widget.pregnancyId, entry);
    final advice = [
      if (sys != null && dia != null && (sys >= calc.highSystolic || dia >= calc.highDiastolic))
        l10n.bpHigh('$sys/$dia'),
      if (entry.temperatureC != null && entry.temperatureC! >= calc.feverFrom)
        l10n.feverAlert(formatDecimal(entry.temperatureC!)),
    ];
    for (final c in [..._fields.values, _diastolic, _notes]) {
      c.clear();
    }
    if (!mounted) return;
    setState(() {
      _feelings.clear();
      _error = null;
      _advice = advice.isEmpty ? null : advice.join('\n');
      _entries = repo.followUps(widget.pregnancyId);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.saved)));
  }

  List<String> _describe(FollowUpEntry e) {
    final l10n = context.l10n;
    return [
      if (e.weightKg != null) '${l10n.paramWeight} ${formatDecimal(e.weightKg!)} kg',
      if (e.systolic != null) '${l10n.paramBloodPressure} ${e.systolic}/${e.diastolic} mmHg',
      if (e.fundalHeightCm != null) '${l10n.paramFundalHeight} ${formatDecimal(e.fundalHeightCm!)} cm',
      if (e.hemoglobinGdl != null) '${l10n.paramHemoglobin} ${formatDecimal(e.hemoglobinGdl!)} g/dL',
      if (e.glucoseGl != null) '${l10n.paramGlucose} ${formatDecimal(e.glucoseGl!, digits: 2)} g/L',
      if (e.temperatureC != null) '${l10n.paramTemperature} ${formatDecimal(e.temperatureC!)} °C',
    ];
  }

  Widget _input(_Param p) {
    final l10n = context.l10n;
    InputDecoration deco(String label) => InputDecoration(labelText: label, prefixIcon: Icon(_icon(p)));
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: switch (p) {
        _Param.bloodPressure => Column(
          children: [
            TextField(
              key: const ValueKey('followup-bp-sys'),
              controller: _fields[p],
              keyboardType: TextInputType.number,
              decoration: deco(l10n.bpSystolic),
            ),
            const Gap(Space.m),
            TextField(
              key: const ValueKey('followup-bp-dia'),
              controller: _diastolic,
              keyboardType: TextInputType.number,
              decoration: deco(l10n.bpDiastolic),
            ),
          ],
        ),
        _ => TextField(
          key: ValueKey('followup-${p.name}'),
          controller: _fields[p],
          keyboardType: decimal,
          decoration: deco(switch (p) {
            _Param.weight => l10n.weightKg,
            _Param.fundalHeight => l10n.fundalHeightCm,
            _Param.hemoglobin => l10n.hemoglobinGdl,
            _Param.glucose => l10n.glucoseGl,
            _ => l10n.temperatureC,
          }),
        ),
      },
    );
  }

  /// Compared without case or accents ("maux" finds "Maux de tête").
  static String _fold(String text) {
    const accents = {
      'à': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', //
      'ô': 'o', 'ù': 'u', 'û': 'u', 'ç': 'c', 'œ': 'oe', '’': "'",
    };
    var t = text.trim().toLowerCase();
    accents.forEach((from, to) => t = t.replaceAll(from, to));
    return t.replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _chosen(String symptom) => _feelings.any((f) => _fold(f) == _fold(symptom));

  /// Adds a symptom (from the list or her own words) once, then empties the
  /// field and keeps it focused, so another one can be searched right away.
  void _addFeeling(String symptom) {
    final text = symptom.trim();
    if (text.isNotEmpty && !_chosen(text)) setState(() => _feelings.add(text));
    _notes.clear();
    _notesFocus.requestFocus();
  }

  /// The proposals for what is typed: the common symptoms containing it, not
  /// chosen yet, then "Ajouter « … »" when her words match none of them.
  List<_Feeling> _feelingOptions(String query) {
    final symptoms = context.l10n.commonSymptoms.split('|');
    final q = _fold(query);
    final options = [
      for (final (i, s) in symptoms.indexed)
        if (!_chosen(s) && (q.isEmpty || _fold(s).contains(q))) _Feeling(s, index: i),
    ];
    final exact = symptoms.any((s) => _fold(s) == q);
    if (q.isNotEmpty && !exact && !_chosen(query)) options.add(_Feeling(query.trim()));
    return options;
  }

  /// "Ce que je ressens": search, choice and free entry in one field. Typing
  /// filters the common symptoms in a compact list right under the field
  /// (about five lines, it scrolls); a proposal is chosen with a tap, or her
  /// own words are added with "Ajouter « … »" or the keyboard's done key.
  /// The chosen symptoms show as chips that can be removed.
  Widget _notesField() {
    final l10n = context.l10n;
    final symptoms = l10n.commonSymptoms.split('|');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_feelings.isNotEmpty) ...[
          Wrap(
            spacing: Space.s,
            runSpacing: Space.xs,
            children: [
              for (final (i, f) in _feelings.indexed)
                InputChip(
                  key: ValueKey('feeling-chip-$i'),
                  label: Text(f),
                  deleteButtonTooltipMessage: l10n.delete,
                  onDeleted: () => setState(() => _feelings.removeAt(i)),
                ),
            ],
          ),
          const Gap(Space.s),
        ],
        LayoutBuilder(
          builder: (context, constraints) => RawAutocomplete<_Feeling>(
            textEditingController: _notes,
            focusNode: _notesFocus,
            displayStringForOption: (o) => o.label,
            optionsBuilder: (value) => _feelingOptions(value.text),
            onSelected: (o) => _addFeeling(o.label),
            fieldViewBuilder: (context, controller, focusNode, _) => TextField(
              key: const ValueKey('followup-notes'),
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              // Done key: the symptom from the list if typed in full, else her own words.
              onSubmitted: (text) {
                final match = symptoms.where((s) => _fold(s) == _fold(text)).firstOrNull;
                _addFeeling(match ?? text);
              },
              decoration: InputDecoration(
                labelText: l10n.notesLabel,
                hintText: l10n.symptomsSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: const Icon(Icons.arrow_drop_down, size: 32),
              ),
            ),
            optionsViewBuilder: (context, onSelected, options) {
              final list = options.toList();
              final highlighted = AutocompleteHighlightedOption.of(context);
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.m),
                    side: const BorderSide(color: AppColors.outline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    // Compact: as wide as the field, about five lines high.
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth,
                      maxHeight: 5 * Space.touch + Space.s,
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: Space.xs),
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final o = list[i];
                        return ListTile(
                          key: ValueKey(o.index == null ? 'symptom-add' : 'symptom-${o.index}'),
                          dense: true,
                          minTileHeight: Space.touch,
                          selected: i == highlighted,
                          leading: Icon(o.index == null ? Icons.add_circle_outline : Icons.healing_outlined),
                          title: Text(o.index == null ? l10n.symptomAdd(o.label) : o.label),
                          onTap: () => onSelected(o),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = dateOnly(AppScope.of(context).services.clock.now());
    return AppScreen(
      title: l10n.followUpTitle,
      bottomAction: FilledButton.icon(
        key: const ValueKey('followup-add'),
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(l10n.save),
      ),
      children: [
        DateField(
          key: const ValueKey('followup-date'),
          label: l10n.measureDate,
          value: _date,
          first: addDays(today, -365),
          last: today,
          onChanged: (d) => setState(() => _date = d),
        ),
        const Gap(Space.l),
        Text(l10n.followUpWhat, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final p in _Param.values)
              FilterChip(
                key: ValueKey('param-${p.name}'),
                // The icon itself shows the choice (never colour alone).
                showCheckmark: false,
                avatar: Icon(_shown.contains(p) ? Icons.check_circle : _icon(p), size: 18),
                label: Text(_label(p)),
                selected: _shown.contains(p),
                onSelected: (v) => setState(() => v ? _shown.add(p) : _shown.remove(p)),
              ),
          ],
        ),
        const Gap(Space.l),
        if (_error != null) ...[
          NoticeBox(icon: Icons.error_outline, tone: Tone.danger, text: _error!),
          const Gap(Space.m),
        ],
        for (final p in _Param.values)
          if (_shown.contains(p)) _input(p),
        _notesField(),
        if (_advice != null) ...[
          const Gap(Space.m),
          NoticeBox(
            key: const ValueKey('followup-advice'),
            icon: Icons.warning_amber,
            tone: Tone.warning,
            text: '$_advice\n${l10n.alertDisclaimer}',
          ),
        ],
        SectionTitle(l10n.childHistory),
        FutureBuilder<List<FollowUpEntry>>(
          future: _entries,
          builder: (context, snap) {
            if (!snap.hasData) return const LoadingView();
            if (snap.data!.isEmpty) return EmptyView(icon: Icons.edit_note, message: l10n.noFollowUp);
            return Column(
              children: [
                for (final e in snap.data!)
                  Card(
                    child: ListTile(
                      title: Text(formatDate(e.date), style: Theme.of(context).textTheme.titleSmall),
                      subtitle: Text([..._describe(e), if (e.notes.isNotEmpty) e.notes].join('\n')),
                      trailing: IconButton(
                        tooltip: l10n.delete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final repo = pregnancyRepository(context);
                          final ok = await confirmAction(
                            context,
                            message: l10n.deleteFollowUp,
                            confirmLabel: l10n.delete,
                            destructive: true,
                          );
                          if (!ok) return;
                          await repo.deleteFollowUp(e.id);
                          setState(() => _entries = repo.followUps(widget.pregnancyId));
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- movements

/// Baby movements (spec §5): the mother can note what she feels at any time,
/// whatever the SA, with an explanation of when they start (16 to 22 SA,
/// config) and of the daily count from 28 SA (config). Each movement is noted
/// with what the mother felt and when. "Le bébé bouge moins" opens the red
/// alert in one tap.
///
/// Message colours: yellow for advice, blue for information, red for alerts.
class MovementsScreen extends StatefulWidget {
  const MovementsScreen({super.key, required this.pregnancyId});
  final String pregnancyId;

  @override
  State<MovementsScreen> createState() => _MovementsScreenState();
}

typedef _MovementsData = (Pregnancy?, Map<DateTime, int>, List<MovementEvent>, AlertContact);

class _MovementsScreenState extends State<MovementsScreen> {
  Future<_MovementsData>? _data;
  MovementType _type = MovementType.kick;

  /// Null: "now" at the moment of saving.
  DateTime? _at;

  Future<_MovementsData> _load() async {
    final repo = pregnancyRepository(context);
    final db = AppScope.read(context).session.active!.db;
    return (
      await repo.current(),
      await repo.movements(widget.pregnancyId),
      await repo.movementEvents(widget.pregnancyId),
      await AlertContact.load(db),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  void _reload() => setState(() {
    _data = _load();
  });

  String _typeLabel(MovementType t) {
    final l10n = context.l10n;
    return switch (t) {
      MovementType.kick => l10n.moveKick,
      MovementType.flutter => l10n.moveFlutter,
      MovementType.roll => l10n.moveRoll,
      MovementType.hiccup => l10n.moveHiccup,
      MovementType.stretch => l10n.moveStretch,
    };
  }

  static IconData _typeIcon(MovementType t) => switch (t) {
    MovementType.kick => Icons.sports_soccer_outlined,
    MovementType.flutter => Icons.air,
    MovementType.roll => Icons.autorenew,
    MovementType.hiccup => Icons.graphic_eq,
    MovementType.stretch => Icons.open_in_full,
  };

  String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final calc = PregnancyCalculator(config);
    final now = scope.services.clock.now();
    final today = dateOnly(now);
    return FutureBuilder<_MovementsData>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final (p, counts, events, contact) = snap.data!;
        if (p == null) return const Scaffold(body: ErrorView());
        final first = calc.firstMovementsWeeks;
        // Day totals: counts of the former counter plus movements noted one by one.
        final perDay = <DateTime, int>{...counts};
        for (final e in events) {
          final d = dateOnly(e.at);
          perDay[d] = (perDay[d] ?? 0) + 1;
        }
        final todayCount = perDay[today] ?? 0;
        final lessSign = asMapList(config.signesDanger['grossesse'])
            .where((s) => s['code'] == 'bebe_bouge_moins')
            .firstOrNull;
        return AppScreen(
          title: l10n.babyMovements,
          bottomAction: FilledButton.icon(
            key: const ValueKey('movements-add'),
            onPressed: () async {
              final at = _at ?? scope.services.clock.now();
              await pregnancyRepository(context).addMovement(p.id, at, _type);
              _reload();
            },
            icon: const Icon(Icons.add),
            label: Text(l10n.movementAdd),
          ),
          children: [
            // Alert (red): one tap opens what to do.
            if (lessSign != null) ...[
              NoticeBox.alert(
                key: const ValueKey('movements-less'),
                text: l10n.movementsLess,
                onTap: () {
                  RedAlertScreen.open(
                    context,
                    config: config,
                    signs: [localizedText(lessSign, context.lang)],
                    contact: contact,
                  );
                  pregnancyRepository(context).recordDanger(p.id, 'bebe_bouge_moins', 'grossesse');
                },
              ),
              const Gap(Space.m),
            ],
            // Information (blue): when movements start, daily count from 28 SA.
            NoticeBox.info(
              key: const ValueKey('movements-info'),
              text: l10n.movementsExplain(first.first, first.last, calc.movementsFromWeeks),
            ),
            const Gap(Space.m),
            // Advice (yellow).
            NoticeBox.tip(key: const ValueKey('movements-tip'), text: l10n.movementsTip),
            const Gap(Space.l),
            LabelWithPill(
              label: Text(l10n.movementsToday, style: Theme.of(context).textTheme.titleMedium),
              pill: Text(
                '$todayCount',
                key: const ValueKey('movements-count'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: AppColors.accent),
              ),
            ),
            SectionTitle(l10n.movementType),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final t in MovementType.values)
                  ChoiceChip(
                    key: ValueKey('movement-type-${t.code}'),
                    showCheckmark: false,
                    avatar: Icon(_type == t ? Icons.check_circle : _typeIcon(t), size: 18),
                    label: Text(_typeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const Gap(Space.m),
            DateField(
              key: const ValueKey('movement-when'),
              label: l10n.movementWhen,
              value: _at,
              withTime: true,
              first: addDays(today, -6),
              last: now,
              initial: now,
              emptyText: l10n.now,
              onChanged: (d) => setState(() => _at = d),
              onCleared: () => setState(() => _at = null),
            ),
            if (events.isNotEmpty) ...[
              SectionTitle(l10n.movementsRecent),
              for (final e in events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_typeIcon(e.type), color: AppColors.accent),
                  title: Text(_typeLabel(e.type)),
                  subtitle: Text('${formatDate(e.at)} · ${_time(e.at)}'),
                  trailing: IconButton(
                    tooltip: l10n.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final repo = pregnancyRepository(context);
                      final ok = await confirmAction(
                        context,
                        message: l10n.deleteMovement,
                        confirmLabel: l10n.delete,
                        destructive: true,
                      );
                      if (!ok) return;
                      await repo.deleteMovement(e.id);
                      _reload();
                    },
                  ),
                ),
            ],
            if (perDay.keys.any((d) => d != today)) ...[
              const Gap(Space.m),
              for (final e
                  in (perDay.entries.where((e) => e.key != today).toList()
                    ..sort((a, b) => b.key.compareTo(a.key))))
                Text(l10n.movementsDay(formatDate(e.key), e.value)),
            ],
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------ delivery

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.pregnancy});
  final Pregnancy pregnancy;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  late DateTime? _date = widget.pregnancy.dates.deliveredOn;
  late String _mode = widget.pregnancy.breastfeeding ?? 'exclusif';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = dateOnly(AppScope.of(context).services.clock.now());
    return AppScreen(
      title: l10n.delivery,
      bottomAction: FilledButton(
        key: const ValueKey('delivery-save'),
        onPressed: _date == null
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                await pregnancyRepository(context).recordDelivery(widget.pregnancy.id, _date!, _mode);
                messenger.showSnackBar(SnackBar(content: Text(l10n.deliverySaved)));
                navigator.pop();
              },
        child: Text(l10n.save),
      ),
      children: [
        DateField(
          key: const ValueKey('delivery-date'),
          label: l10n.deliveryDate,
          value: _date,
          first: addDays(today, -365),
          last: today,
          onChanged: (d) => setState(() => _date = d),
        ),
        SectionTitle(l10n.breastfeedingMode),
        RadioGroup<String>(
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v!),
          child: Column(
            children: [
              for (final (v, label) in [
                ('exclusif', l10n.bfExclusive),
                ('mixte', l10n.bfMixed),
                ('aucun', l10n.bfNone),
              ])
                RadioListTile<String>(value: v, title: Text(label)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- women diet

/// Optional women's dietary diversity (MDD-W, 10 groups from the config).
class WomenDietScreen extends StatefulWidget {
  const WomenDietScreen({super.key});

  @override
  State<WomenDietScreen> createState() => _WomenDietScreenState();
}

class _WomenDietScreenState extends State<WomenDietScreen> {
  Set<int>? _eaten;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_eaten != null) return;
    pregnancyRepository(context).dietOn(AppScope.read(context).services.clock.now()).then((g) {
      if (mounted) setState(() => _eaten = g);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scope = AppScope.of(context);
    final config = scope.services.config.current;
    final diet = WomenDiet(config);
    final eaten = _eaten;
    if (eaten == null) return const Scaffold(body: LoadingView());
    // Each food name is shown only once (see WomenDiet.shown).
    final shown = diet.shown(context.lang);
    final ok = diet.metShown(eaten, context.lang);
    final count = diet.eatenShown(eaten, context.lang).length;
    return AppScreen(
      title: l10n.womenDiet,
      bottomAction: Container(
        padding: const EdgeInsets.all(Space.m),
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(Radii.m)),
        child: LabelWithPill(
          label: Text(l10n.womenDietScore(count), style: Theme.of(context).textTheme.titleMedium),
          pill: StatusPill(
            icon: ok ? Icons.check_circle_outline : Icons.error_outline,
            label: ok ? l10n.diversityOk : l10n.diversityLow,
            tone: ok ? Tone.success : Tone.warning,
          ),
        ),
      ),
      children: [
        Text(l10n.womenDietHint),
        const Gap(Space.m),
        for (final (i, label) in shown)
          CheckboxListTile(
            key: ValueKey('women-group-$i'),
            value: eaten.contains(i),
            title: Text(label),
            onChanged: (v) async {
              final next = {...eaten};
              v == true ? next.add(i) : next.remove(i);
              setState(() => _eaten = next);
              await pregnancyRepository(context).setDiet(scope.services.clock.now(), next);
            },
          ),
        const Gap(Space.m),
        Text(config.sourceLabel('alimentation_femme'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// A proposal of "Ce que je ressens": a common symptom (its [index] in the
/// list) or her own words ([index] null).
class _Feeling {
  const _Feeling(this.label, {this.index});
  final String label;
  final int? index;
}
