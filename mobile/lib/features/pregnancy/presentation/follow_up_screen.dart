import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/alert_contact.dart';
import '../../../core/alerts/red_alert_screen.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/pregnancy_repository.dart';
import '../domain/follow_up_checks.dart';
import '../domain/pregnancy.dart';
import 'pregnancy_home_screen.dart';
import 'trend_chart.dart';

/// Health parameters of "Mon suivi". Each one is optional; one entry is dated.
enum _Param { weight, bloodPressure, fundalHeight, hemoglobin, glucose, temperature }

typedef _FollowUpData = (Pregnancy?, List<FollowUpEntry>);

/// "Mon suivi de grossesse": not only to keep numbers, but to understand them.
///
/// - Entry: date, who took the measurement (at home or a health
///   professional), the chosen measurements, and "Ce que je ressens" (quick
///   symptoms in one tap, plus the search of the common symptoms).
/// - Worrying values (blood pressure, temperature, blood sugar, haemoglobin,
///   with the symptoms) are read at once, with what to do during pregnancy;
///   the urgent ones open the red alert in one tap.
/// - Evolution: weight and blood pressure over the weeks (SA).
/// - History: each entry with its origin and its worrying values; it can be
///   corrected or deleted.
///
/// Message colours: always with an icon and a word (never colour alone).
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
  final Set<_Param> _shown = {_Param.weight, _Param.bloodPressure};
  DateTime? _date;
  MeasureSource _source = MeasureSource.home;
  bool _glucoseFasting = false;

  /// The entry being corrected (null: a new one).
  FollowUpEntry? _editing;
  Future<_FollowUpData>? _data;
  String? _error;

  /// What the last saved entry showed (worrying values), with its values.
  List<(FlagKind, String)> _flags = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _date ??= dateOnly(AppScope.read(context).services.clock.now());
    _data ??= _load();
  }

  Future<_FollowUpData> _load() async {
    final repo = pregnancyRepository(context);
    return (await repo.current(), await repo.followUps(widget.pregnancyId));
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

  // ------------------------------------------------------------- symptoms

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

  List<String> get _quickLabels => context.l10n.quickSymptoms.split('|');

  /// The quick symptoms among the chosen ones (from the chips, the list or
  /// typed in full): they are read with the values.
  Set<QuickSymptom> _quickChosen(List<String> feelings) {
    final labels = _quickLabels;
    return {
      for (final (i, label) in labels.indexed)
        if (i < QuickSymptom.values.length && feelings.any((f) => _fold(f) == _fold(label)))
          QuickSymptom.values[i],
    };
  }

  /// Adds a symptom (from the list or her own words) once, then empties the
  /// field and keeps it focused, so another one can be searched right away.
  void _addFeeling(String symptom) {
    final text = symptom.trim();
    if (text.isNotEmpty && !_chosen(text)) setState(() => _feelings.add(text));
    _notes.clear();
    _notesFocus.requestFocus();
  }

  void _toggleQuick(String label) => setState(() {
    if (_chosen(label)) {
      _feelings.removeWhere((f) => _fold(f) == _fold(label));
    } else {
      _feelings.add(label);
    }
  });

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

  // ------------------------------------------------------- reading values

  List<(FlagKind, String)> _assess(FollowUpEntry e, {Set<QuickSymptom> symptoms = const {}}) {
    final limits = FollowUpLimits(AppScope.read(context).services.config.current);
    return [
      for (final k in assessFollowUp(
        limits,
        systolic: e.systolic,
        diastolic: e.diastolic,
        temperatureC: e.temperatureC,
        glucoseGl: e.glucoseGl,
        glucoseFasting: e.glucoseFasting,
        hemoglobinGdl: e.hemoglobinGdl,
        symptoms: symptoms,
      ))
        (k, _valueOf(k, e)),
    ];
  }

  static String _valueOf(FlagKind k, FollowUpEntry e) => switch (k) {
    FlagKind.bpSevere ||
    FlagKind.bpHigh ||
    FlagKind.bpLow ||
    FlagKind.preEclampsiaUrgent => '${e.systolic}/${e.diastolic}',
    FlagKind.feverHigh || FlagKind.fever => formatDecimal(e.temperatureC ?? 0),
    FlagKind.glucoseLow ||
    FlagKind.glucoseVeryHigh ||
    FlagKind.glucoseHighFasting ||
    FlagKind.glucoseToCheck => formatDecimal(e.glucoseGl ?? 0, digits: 2),
    FlagKind.anaemiaSevere || FlagKind.anaemia => formatDecimal(e.hemoglobinGdl ?? 0),
    _ => '',
  };

  String _flagTitle(FlagKind k, String v) {
    final l10n = context.l10n;
    return switch (k) {
      FlagKind.bpSevere => l10n.flagBpSevere(v),
      FlagKind.bpHigh => l10n.flagBpHigh(v),
      FlagKind.bpLow => l10n.flagBpLow(v),
      FlagKind.feverHigh => l10n.flagFeverHigh(v),
      FlagKind.fever => l10n.flagFever(v),
      FlagKind.glucoseLow => l10n.flagGlucoseLow(v),
      FlagKind.glucoseVeryHigh => l10n.flagGlucoseVeryHigh(v),
      FlagKind.glucoseHighFasting => l10n.flagGlucoseHighFasting(v),
      FlagKind.glucoseToCheck => l10n.flagGlucoseToCheck(v),
      FlagKind.anaemiaSevere => l10n.flagAnaemiaSevere(v),
      FlagKind.anaemia => l10n.flagAnaemia(v),
      FlagKind.preEclampsiaUrgent => l10n.flagPreEclampsiaUrgent(v),
      FlagKind.preEclampsiaSigns => l10n.flagPreEclampsiaSigns,
      FlagKind.breathless => l10n.flagBreathless,
      FlagKind.dizzy => l10n.flagDizzy,
    };
  }

  String _flagAdvice(FlagKind k) {
    final l10n = context.l10n;
    return switch (k) {
      FlagKind.bpSevere => l10n.adviceBpSevere,
      FlagKind.bpHigh => l10n.adviceBpHigh,
      FlagKind.bpLow => l10n.adviceBpLow,
      FlagKind.feverHigh => l10n.adviceFeverHigh,
      FlagKind.fever => l10n.adviceFever,
      FlagKind.glucoseLow => l10n.adviceGlucoseLow,
      FlagKind.glucoseVeryHigh => l10n.adviceGlucoseVeryHigh,
      FlagKind.glucoseHighFasting => l10n.adviceGlucoseHighFasting,
      FlagKind.glucoseToCheck => l10n.adviceGlucoseToCheck,
      FlagKind.anaemiaSevere => l10n.adviceAnaemiaSevere,
      FlagKind.anaemia => l10n.adviceAnaemia,
      FlagKind.preEclampsiaUrgent => l10n.advicePreEclampsiaUrgent,
      FlagKind.preEclampsiaSigns => l10n.advicePreEclampsiaSigns,
      FlagKind.breathless => l10n.adviceBreathless,
      FlagKind.dizzy => l10n.adviceDizzy,
    };
  }

  static Tone _tone(FlagLevel l) => switch (l) {
    FlagLevel.urgent => Tone.danger,
    FlagLevel.warning => Tone.warning,
    FlagLevel.info => Tone.info,
  };

  static IconData _levelIcon(FlagLevel l) => switch (l) {
    FlagLevel.urgent => Icons.emergency_outlined,
    FlagLevel.warning => Icons.warning_amber_rounded,
    FlagLevel.info => Icons.info_outline,
  };

  String _levelWord(FlagLevel l) {
    final l10n = context.l10n;
    return switch (l) {
      FlagLevel.urgent => l10n.flagLevelUrgent,
      FlagLevel.warning => l10n.flagLevelToday,
      FlagLevel.info => l10n.flagLevelWatch,
    };
  }

  void _openAlert(String title) {
    final config = AppScope.read(context).services.config.current;
    RedAlertScreen.open(
      context,
      config: config,
      signs: [
        {'code': 'suivi', context.lang: title},
      ],
      contact: const AlertContact(),
    );
  }

  // ----------------------------------------------------------------- save

  Future<void> _save() async {
    final l10n = context.l10n;
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
    final feelings = [..._feelings, if (_notes.text.trim().isNotEmpty) _notes.text.trim()];
    final entry = FollowUpEntry(
      id: _editing?.id ?? '',
      date: _date!,
      weightKg: values[_Param.weight],
      systolic: values[_Param.bloodPressure]?.round(),
      diastolic: dia,
      fundalHeightCm: values[_Param.fundalHeight],
      hemoglobinGdl: values[_Param.hemoglobin],
      glucoseGl: values[_Param.glucose],
      glucoseFasting: values.containsKey(_Param.glucose) ? _glucoseFasting : null,
      temperatureC: values[_Param.temperature],
      notes: feelings.join(', '),
      source: _source,
    );
    if (entry.isEmpty) {
      setState(() => _error = l10n.followUpEmpty);
      return;
    }
    final repo = pregnancyRepository(context);
    final messenger = ScaffoldMessenger.of(context);
    final flags = _assess(entry, symptoms: _quickChosen(feelings));
    _editing == null ? await repo.addFollowUp(widget.pregnancyId, entry) : await repo.updateFollowUp(entry);
    if (!mounted) return;
    final corrected = _editing != null;
    _clearForm();
    setState(() {
      _flags = flags;
      _data = _load();
    });
    messenger.showSnackBar(SnackBar(content: Text(corrected ? l10n.followUpCorrected : l10n.saved)));
  }

  void _clearForm() {
    for (final c in [..._fields.values, _diastolic, _notes]) {
      c.clear();
    }
    _feelings.clear();
    _error = null;
    _editing = null;
    _glucoseFasting = false;
  }

  /// Puts an entry back in the form, to correct it.
  void _edit(FollowUpEntry e) {
    String n(double? v, {int digits = 1}) => v == null ? '' : formatDecimal(v, digits: digits);
    setState(() {
      _clearForm();
      _editing = e;
      _flags = const [];
      _date = e.date;
      _source = e.source;
      _glucoseFasting = e.glucoseFasting ?? false;
      _fields[_Param.weight]!.text = n(e.weightKg);
      _fields[_Param.bloodPressure]!.text = e.systolic?.toString() ?? '';
      _diastolic.text = e.diastolic?.toString() ?? '';
      _fields[_Param.fundalHeight]!.text = n(e.fundalHeightCm);
      _fields[_Param.hemoglobin]!.text = n(e.hemoglobinGdl);
      _fields[_Param.glucose]!.text = n(e.glucoseGl, digits: 2);
      _fields[_Param.temperature]!.text = n(e.temperatureC);
      _shown
        ..clear()
        ..addAll([
          for (final p in _Param.values)
            if (_fields[p]!.text.isNotEmpty) p,
        ]);
      if (_shown.isEmpty) _shown.add(_Param.weight);
      _feelings.addAll(e.notes.split(', ').where((s) => s.trim().isNotEmpty));
    });
    final scroll = PrimaryScrollController.maybeOf(context);
    if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
  }

  void _cancelEdit() => setState(_clearForm);

  Future<void> _delete(FollowUpEntry e) async {
    final l10n = context.l10n;
    final repo = pregnancyRepository(context);
    final ok = await confirmAction(
      context,
      message: l10n.deleteFollowUp,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!ok) return;
    await repo.deleteFollowUp(e.id);
    if (!mounted) return;
    setState(() {
      if (_editing?.id == e.id) _clearForm();
      _data = _load();
    });
  }

  // --------------------------------------------------------------- widgets

  Widget _input(_Param p) {
    final l10n = context.l10n;
    InputDecoration deco(String label) => InputDecoration(labelText: label, prefixIcon: Icon(_icon(p)));
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: switch (p) {
        _Param.bloodPressure => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('followup-bp-sys'),
                controller: _fields[p],
                keyboardType: TextInputType.number,
                decoration: deco(l10n.bpSystolic),
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: TextField(
                key: const ValueKey('followup-bp-dia'),
                controller: _diastolic,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.bpDiastolic),
              ),
            ),
          ],
        ),
        _Param.glucose => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('followup-glucose'),
              controller: _fields[p],
              keyboardType: decimal,
              decoration: deco(l10n.glucoseGl),
            ),
            CheckboxListTile(
              key: const ValueKey('followup-glucose-fasting'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _glucoseFasting,
              onChanged: (v) => setState(() => _glucoseFasting = v ?? false),
              title: Text(l10n.glucoseFasting),
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
            _ => l10n.temperatureC,
          }),
        ),
      },
    );
  }

  /// Who took the measurement: two clear choices with an icon.
  Widget _sourceChoice() {
    return Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (final s in MeasureSource.values)
          ChoiceChip(
            key: ValueKey('followup-source-${s.code}'),
            showCheckmark: false,
            avatar: Icon(_source == s ? Icons.check_circle : _sourceIcon(s), size: 18),
            label: Text(_sourceLabel(s)),
            selected: _source == s,
            onSelected: (_) => setState(() => _source = s),
          ),
      ],
    );
  }

  static IconData _sourceIcon(MeasureSource s) => switch (s) {
    MeasureSource.home => Icons.home_outlined,
    MeasureSource.professional => Icons.medical_services_outlined,
  };

  String _sourceLabel(MeasureSource s) => switch (s) {
    MeasureSource.home => context.l10n.sourceHome,
    MeasureSource.professional => context.l10n.sourceProfessional,
  };

  /// "Ce que je ressens": the frequent symptoms in one tap, then the search
  /// of the common symptoms (or her own words) in one field. The chosen
  /// ones show as chips that can be removed.
  Widget _notesField() {
    final l10n = context.l10n;
    final symptoms = l10n.commonSymptoms.split('|');
    final quick = _quickLabels;
    final others = [
      for (final (i, f) in _feelings.indexed)
        if (!quick.any((q) => _fold(q) == _fold(f))) (i, f),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.notesLabel, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final (i, q) in quick.indexed)
              FilterChip(
                key: ValueKey('quick-symptom-$i'),
                showCheckmark: false,
                avatar: Icon(_chosen(q) ? Icons.check_circle : Icons.add_circle_outline, size: 18),
                label: Text(q),
                selected: _chosen(q),
                onSelected: (_) => _toggleQuick(q),
              ),
          ],
        ),
        const Gap(Space.m),
        if (others.isNotEmpty) ...[
          Wrap(
            spacing: Space.s,
            runSpacing: Space.xs,
            children: [
              for (final (i, f) in others)
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
                labelText: l10n.symptomsOther,
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

  /// One worrying value: what it is, how urgent (icon + word), what to do.
  /// The urgent ones open the red alert (call the health centre).
  Widget _flagBox((FlagKind, String) flag, {Key? key}) {
    final l10n = context.l10n;
    final (kind, value) = flag;
    final title = _flagTitle(kind, value);
    final urgent = kind.level == FlagLevel.urgent;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: NoticeBox(
        key: key,
        icon: _levelIcon(kind.level),
        tone: _tone(kind.level),
        title: '${_levelWord(kind.level)} · $title',
        text: urgent ? '${_flagAdvice(kind)}\n${l10n.flagOpenAlert}' : _flagAdvice(kind),
        onTap: urgent ? () => _openAlert(title) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = dateOnly(AppScope.of(context).services.clock.now());
    final editing = _editing;
    return AppScreen(
      title: l10n.followUpTitle,
      bottomAction: FilledButton.icon(
        key: const ValueKey('followup-add'),
        onPressed: _save,
        icon: Icon(editing == null ? Icons.add : Icons.check),
        label: Text(editing == null ? l10n.save : l10n.followUpSaveCorrection),
      ),
      children: [
        if (editing != null) ...[
          NoticeBox(
            key: const ValueKey('followup-editing'),
            icon: Icons.edit_outlined,
            text: l10n.followUpEditing(formatDate(editing.date)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('followup-cancel-edit'),
              onPressed: _cancelEdit,
              child: Text(l10n.followUpCancelEdit),
            ),
          ),
        ],
        if (_flags.isNotEmpty) ...[
          for (final (i, f) in _flags.indexed) _flagBox(f, key: ValueKey('followup-flag-$i')),
          Text(
            l10n.alertDisclaimer,
            key: const ValueKey('followup-advice'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Gap(Space.l),
        ],
        DateField(
          key: const ValueKey('followup-date'),
          label: l10n.measureDate,
          value: _date,
          first: addDays(today, -365),
          last: today,
          onChanged: (d) => setState(() => _date = d),
        ),
        const Gap(Space.m),
        Text(l10n.sourceQuestion, style: Theme.of(context).textTheme.titleSmall),
        const Gap(Space.s),
        _sourceChoice(),
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
        FutureBuilder<_FollowUpData>(
          future: _data,
          builder: (context, snap) {
            if (!snap.hasData) return const LoadingView();
            final (pregnancy, entries) = snap.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._evolution(pregnancy, entries),
                SectionTitle(l10n.followUpHistory),
                if (entries.isEmpty)
                  EmptyView(icon: Icons.edit_note, message: l10n.noFollowUp)
                else
                  for (final e in entries) _historyCard(pregnancy, e),
              ],
            );
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------------ evolution

  /// Weight and blood pressure over the weeks of pregnancy.
  List<Widget> _evolution(Pregnancy? pregnancy, List<FollowUpEntry> entries) {
    if (pregnancy == null) return const [];
    final l10n = context.l10n;
    final config = AppScope.of(context).services.config.current;
    final calc = PregnancyCalculator(config);
    final limits = FollowUpLimits(config);
    double? weeksOf(FollowUpEntry e) {
      final ga = calc.age(pregnancy.dates, e.date);
      return ga == null || ga.totalDays < 0 ? null : ga.totalDays / 7;
    }

    final weight = <TrendPoint>[];
    final sys = <TrendPoint>[];
    final dia = <TrendPoint>[];
    for (final e in entries.reversed) {
      final w = weeksOf(e);
      if (w == null) continue;
      if (e.weightKg != null) weight.add(TrendPoint(w, e.weightKg!));
      if (e.systolic != null && e.diastolic != null) {
        sys.add(TrendPoint(w, e.systolic!.toDouble()));
        dia.add(TrendPoint(w, e.diastolic!.toDouble()));
      }
    }
    if (weight.isEmpty && sys.isEmpty) return const [];
    final text = Theme.of(context).textTheme;
    String wk(double w) => w.floor().toString();
    return [
      SectionTitle(l10n.followUpEvolution),
      if (weight.isNotEmpty) ...[
        Text(l10n.paramWeight, style: text.titleSmall),
        Text(
          weight.length == 1
              ? l10n.trendWeightOne(formatDecimal(weight.last.value), wk(weight.last.weeks))
              : l10n.trendWeight(
                  formatDecimal(weight.last.value),
                  wk(weight.last.weeks),
                  (weight.last.value - weight.first.value >= 0 ? '+' : '') +
                      formatDecimal(weight.last.value - weight.first.value),
                  wk(weight.first.weeks),
                ),
          key: const ValueKey('trend-weight-summary'),
          style: text.bodyMedium,
        ),
        const Gap(Space.s),
        TrendChart(
          key: const ValueKey('trend-weight'),
          series: [TrendSeries(label: l10n.paramWeight, points: weight, color: AppColors.accent)],
          semanticLabel: l10n.trendWeightOne(formatDecimal(weight.last.value), wk(weight.last.weeks)),
          weeksLabel: l10n.weeksShort,
          step: 2,
        ),
        const Gap(Space.l),
      ],
      if (sys.isNotEmpty) ...[
        Text(l10n.paramBloodPressure, style: text.titleSmall),
        Text(
          l10n.trendBp('${sys.last.value.round()}/${dia.last.value.round()}', wk(sys.last.weeks)),
          key: const ValueKey('trend-bp-summary'),
          style: text.bodyMedium,
        ),
        const Gap(Space.s),
        TrendChart(
          key: const ValueKey('trend-bp'),
          series: [
            TrendSeries(label: l10n.bpSystolicShort, points: sys, color: AppColors.danger),
            TrendSeries(label: l10n.bpDiastolicShort, points: dia, color: AppColors.accent, square: true),
          ],
          limits: [
            TrendLimit(limits.highSystolic.toDouble(), AppColors.danger),
            TrendLimit(limits.highDiastolic.toDouble(), AppColors.warning),
          ],
          semanticLabel: l10n.trendBp(
            '${sys.last.value.round()}/${dia.last.value.round()}',
            wk(sys.last.weeks),
          ),
          weeksLabel: l10n.weeksShort,
          step: 10,
        ),
        Text(
          l10n.trendBpLimits('${limits.highSystolic}/${limits.highDiastolic}'),
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    ];
  }

  // -------------------------------------------------------------- history

  List<String> _describe(FollowUpEntry e) {
    final l10n = context.l10n;
    return [
      if (e.weightKg != null) '${l10n.paramWeight} ${formatDecimal(e.weightKg!)} kg',
      if (e.systolic != null) '${l10n.paramBloodPressure} ${e.systolic}/${e.diastolic} mmHg',
      if (e.fundalHeightCm != null) '${l10n.paramFundalHeight} ${formatDecimal(e.fundalHeightCm!)} cm',
      if (e.hemoglobinGdl != null) '${l10n.paramHemoglobin} ${formatDecimal(e.hemoglobinGdl!)} g/dL',
      if (e.glucoseGl != null)
        '${l10n.paramGlucose} ${formatDecimal(e.glucoseGl!, digits: 2)} g/L'
            '${e.glucoseFasting == true ? ' (${l10n.glucoseFastingShort})' : ''}',
      if (e.temperatureC != null) '${l10n.paramTemperature} ${formatDecimal(e.temperatureC!)} °C',
    ];
  }

  Widget _historyCard(Pregnancy? pregnancy, FollowUpEntry e) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final calc = PregnancyCalculator(AppScope.of(context).services.config.current);
    final ga = pregnancy == null ? null : calc.age(pregnancy.dates, e.date);
    final flags = _assess(e, symptoms: _quickChosen(e.notes.split(', ')));
    final editing = _editing?.id == e.id;
    return Card(
      key: ValueKey('followup-entry-${e.id}'),
      shape: editing
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.m),
              side: const BorderSide(color: AppColors.accent, width: 2),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.m),
        onTap: () => _edit(e),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        formatDate(e.date),
                        if (ga != null && ga.totalDays >= 0) l10n.weeksValue(ga.weeks),
                      ].join(' · '),
                      style: text.titleSmall,
                    ),
                    const Gap(Space.xs),
                    Row(
                      children: [
                        Icon(_sourceIcon(e.source), size: 16, color: AppColors.textMuted),
                        const SizedBox(width: Space.xs),
                        Flexible(
                          child: Text(
                            _sourceLabel(e.source),
                            key: ValueKey('followup-entry-source-${e.id}'),
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                    const Gap(Space.xs),
                    Text([..._describe(e), if (e.notes.isNotEmpty) e.notes].join('\n')),
                    for (final (kind, value) in flags)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_levelIcon(kind.level), size: 18, color: _tone(kind.level).foreground),
                            const SizedBox(width: Space.xs),
                            Expanded(
                              child: Text(
                                '${_levelWord(kind.level)} · ${_flagTitle(kind, value)}',
                                style: text.bodySmall?.copyWith(
                                  color: _tone(kind.level).foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    key: ValueKey('followup-edit-${e.id}'),
                    tooltip: l10n.edit,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(e),
                  ),
                  IconButton(
                    key: ValueKey('followup-delete-${e.id}'),
                    tooltip: l10n.delete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(e),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
