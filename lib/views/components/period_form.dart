import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../cores/l10n/labels.dart';
import '../../cores/models/cycle.dart';
import '../../cores/providers/cycle_providers.dart';
import '../../cores/providers/language_provider.dart';
import '../../cores/services/cycle_timeline.dart';
import '../../cores/services/days.dart';
import '../../cores/themes/app_colors.dart';
import 'month_calendar.dart';

/// Saisie ou correction d'un cycle. Seule la date de début est obligatoire, et
/// aujourd'hui est proposé d'office : deux touches suffisent à enregistrer.
class PeriodForm extends ConsumerStatefulWidget {
  const PeriodForm({
    super.key,
    required this.timeline,
    this.initial,
    this.onSaved,
  });

  final CycleTimeline timeline;

  /// Cycle à corriger ; `null` pour une nouvelle saisie.
  final Cycle? initial;
  final VoidCallback? onSaved;

  @override
  ConsumerState<PeriodForm> createState() => _PeriodFormState();
}

class _PeriodFormState extends ConsumerState<PeriodForm> {
  late DateTime _today;
  late DateTime _start;
  DateTime? _end;
  int? _intensity;
  late Set<String> _symptoms;
  final _cycleLength = TextEditingController();
  final _periodLength = TextEditingController();
  final _otherSymptoms = TextEditingController();
  String? _startError;
  String? _cycleLengthError;
  String? _periodLengthError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _today = dayOf(ref.read(clockProvider)());
    _fillFrom(widget.initial);
  }

  void _fillFrom(Cycle? cycle) {
    _start = parseDay(cycle?.dateDebut) ?? _today;
    _end = parseDay(cycle?.dateFin);
    _intensity = PeriodIntensity.decode(cycle?.intensite);
    final symptoms = PeriodSymptom.decode(cycle?.symptome);
    _symptoms = symptoms.where(PeriodSymptom.values.contains).toSet();
    _otherSymptoms.text = symptoms
        .where((s) => !PeriodSymptom.values.contains(s))
        .join(', ');
    _cycleLength.text = _editsCycleLength ? '${cycle?.dureCycle ?? ''}' : '';
    _periodLength.text = '${cycle?.dureRegle ?? ''}';
    _startError = null;
    _cycleLengthError = null;
    _periodLengthError = null;
  }

  /// Sur un cycle terminé, `dure_cycle` est mesurée : rien à saisir.
  bool get _editsCycleLength {
    final initial = widget.initial;
    return initial == null ||
        widget.timeline.cycles.isEmpty ||
        widget.timeline.cycles.last.id == initial.id;
  }

  @override
  void dispose() {
    _cycleLength.dispose();
    _periodLength.dispose();
    _otherSymptoms.dispose();
    super.dispose();
  }

  bool _startIsTaken(DateTime start) => widget.timeline.cycles.any(
    (c) => c.id != widget.initial?.id && parseDay(c.dateDebut) == start,
  );

  /// Les deux dates donnent la durée des règles, qui reste modifiable.
  void _syncPeriodLength() {
    final end = _end;
    if (end != null) {
      _periodLength.text = '${daysBetween(_start, end) + 1}';
      _periodLengthError = null;
    }
  }

  Future<void> _pickStart(AppLanguage language) async {
    final picked = await showDayPicker(
      context,
      language: language,
      today: _today,
      initialDay: _start,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = picked;
      _startError = null;
      // Une date de fin antérieure au nouveau début n'a plus de sens.
      if (_end?.isBefore(picked) ?? false) _end = null;
      _syncPeriodLength();
    });
  }

  Future<void> _pickEnd(AppLanguage language) async {
    final picked = await showDayPicker(
      context,
      language: language,
      today: _today,
      initialDay: _end ?? _start,
      firstDay: _start,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _end = picked;
      _syncPeriodLength();
    });
  }

  String _rangeError(AppLanguage language, int min, int max) => language.pick(
    mg: 'Ampidiro isa eo anelanelan’ny $min sy $max.',
    fr: 'Indiquez un nombre entre $min et $max.',
  );

  Future<void> _save(AppLanguage language) async {
    final cycleLength = int.tryParse(_cycleLength.text.trim());
    final periodLength = int.tryParse(_periodLength.text.trim());
    setState(() {
      _startError = _startIsTaken(_start)
          ? language.pick(
              mg: 'Efa voarakitra io daty io.',
              fr: 'Cette date est déjà enregistrée.',
            )
          : null;
      _cycleLengthError =
          cycleLength != null && !CycleRules.isPlausibleLength(cycleLength)
          ? _rangeError(
              language,
              CycleRules.minPlausibleLength,
              CycleRules.maxPlausibleLength,
            )
          : null;
      _periodLengthError =
          periodLength != null && !CycleRules.isPlausiblePeriod(periodLength)
          ? _rangeError(
              language,
              CycleRules.minPeriodLength,
              CycleRules.maxPeriodLength,
            )
          : null;
    });
    if (_startError != null ||
        _cycleLengthError != null ||
        _periodLengthError != null) {
      return;
    }

    final initial = widget.initial;
    final cycle = Cycle(
      id: initial?.id,
      dateDebut: formatDay(_start),
      dateFin: _end == null ? null : formatDay(_end!),
      intensite: PeriodIntensity.encode(_intensity),
      dureCycle: _editsCycleLength ? cycleLength : initial?.dureCycle,
      dureRegle: periodLength,
      symptome: PeriodSymptom.encode(
        PeriodSymptom.values.where(_symptoms.contains),
        _otherSymptoms.text,
      ),
      estimationProchain: initial?.estimationProchain,
      userId: initial?.userId,
    );

    setState(() => _saving = true);
    try {
      await ref.read(cycleJournalProvider).save(cycle);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            language.pick(
              mg: 'Tsy voatahiry. Andramo indray.',
              fr: 'Enregistrement impossible. Veuillez réessayer.',
            ),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (initial == null) _fillFrom(null);
    });
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        _DateButton(
          key: const ValueKey('period-start'),
          label: language.pick(
            mg: 'Daty nanombohan’ny fadimbolana',
            fr: 'Date de début des règles',
          ),
          value: language.formatDate(_start),
          errorText: _startError,
          onPressed: () => _pickStart(language),
        ),
        Theme(
          // Retire les filets que l'ExpansionTile ajoute à l'ouverture.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const ValueKey('period-details'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
            iconColor: AppColors.primaryDark,
            collapsedIconColor: AppColors.primaryDark,
            initiallyExpanded: widget.initial != null,
            maintainState: true,
            title: Text(
              language.pick(
                mg: 'Antsipiriany fanampiny (tsy voatery)',
                fr: 'Plus de détails (facultatif)',
              ),
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: _details(language),
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('period-save'),
          onPressed: _saving ? null : () => _save(language),
          icon: const Icon(Symbols.check),
          label: Text(language.pick(mg: 'Tehirizo', fr: 'Enregistrer')),
        ),
      ],
    );
  }

  List<Widget> _details(AppLanguage language) {
    final titleStyle = Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700);
    return [
      _DateButton(
        key: const ValueKey('period-end'),
        label: language.pick(mg: 'Daty niafarany', fr: 'Date de fin'),
        value: _end == null
            ? language.pick(mg: 'Tsy voafidy', fr: 'Non renseignée')
            : language.formatDate(_end!),
        onPressed: () => _pickEnd(language),
        onClear: _end == null ? null : () => setState(() => _end = null),
        clearTooltip: language.pick(mg: 'Fafao', fr: 'Effacer'),
      ),
      const SizedBox(height: 16),
      _NumberField(
        fieldKey: const ValueKey('period-length'),
        controller: _periodLength,
        label: language.pick(
          mg: 'Faharetan’ny fadimbolana (andro)',
          fr: 'Durée des règles (jours)',
        ),
        helper: language.pick(
          mg:
              'Raha tsy fantatrao, ${CycleRules.defaultPeriodLength} andro no '
              'raisina.',
          fr:
              'Si vous ne la connaissez pas, '
              '${CycleRules.defaultPeriodLength} jours seront retenus.',
        ),
        errorText: _periodLengthError,
      ),
      if (_editsCycleLength) ...[
        const SizedBox(height: 16),
        _NumberField(
          fieldKey: const ValueKey('cycle-length'),
          controller: _cycleLength,
          label: language.pick(
            mg: 'Faharetan’ny tsingerina (andro)',
            fr: 'Durée du cycle (jours)',
          ),
          helper: language.pick(
            mg:
                'Raha tsy fantatrao, ny salan’isa na '
                '${CycleRules.defaultCycleLength} andro no raisina.',
            fr:
                'Si vous ne la connaissez pas, votre moyenne ou '
                '${CycleRules.defaultCycleLength} jours seront retenus.',
          ),
          errorText: _cycleLengthError,
        ),
      ],
      const SizedBox(height: 16),
      Text(
        language.pick(mg: 'Habetsahan’ny rà', fr: 'Intensité'),
        style: titleStyle,
      ),
      const SizedBox(height: 4),
      _IntensityScale(
        language: language,
        level: _intensity,
        onChanged: (level) => setState(() => _intensity = level),
      ),
      const SizedBox(height: 16),
      Text(
        language.pick(mg: 'Soritr’aretina', fr: 'Symptômes'),
        style: titleStyle,
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        children: [
          for (final code in PeriodSymptom.values)
            FilterChip(
              key: ValueKey('symptom-$code'),
              label: Text(language.symptomName(code)),
              selected: _symptoms.contains(code),
              onSelected: (selected) => setState(
                () => selected ? _symptoms.add(code) : _symptoms.remove(code),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('symptom-other'),
        controller: _otherSymptoms,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: language.pick(
            mg: 'Hafa (soraty eto)',
            fr: 'Autre (à préciser)',
          ),
        ),
      ),
    ];
  }
}

/// Échelle de 1 à 5 gouttes. Toucher le niveau choisi le retire, le champ étant
/// facultatif.
class _IntensityScale extends StatelessWidget {
  const _IntensityScale({
    required this.language,
    required this.level,
    required this.onChanged,
  });

  final AppLanguage language;
  final int? level;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final level = this.level;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: [
            for (final value in PeriodIntensity.levels)
              Semantics(
                button: true,
                selected: value == level,
                label:
                    '$value / ${PeriodIntensity.levels.last}, '
                    '${language.intensityName('$value')}',
                excludeSemantics: true,
                child: InkResponse(
                  key: ValueKey('intensity-$value'),
                  onTap: () => onChanged(value == level ? null : value),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      Symbols.water_drop,
                      size: 32,
                      fill: level != null && value <= level ? 1 : 0,
                      color: level != null && value <= level
                          ? AppColors.red
                          : AppColors.ink,
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Le mot double le nombre de gouttes, sans dépendre de la couleur.
        Text(
          level == null
              ? language.pick(mg: 'Tsy voafidy', fr: 'Non renseignée')
              : language.intensityName('$level'),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.helper,
    required this.errorText,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String helper;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        errorText: errorText,
        errorMaxLines: 2,
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    super.key,
    required this.label,
    required this.value,
    required this.onPressed,
    this.errorText,
    this.onClear,
    this.clearTooltip,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;
  final String? errorText;
  final VoidCallback? onClear;
  final String? clearTooltip;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          errorMaxLines: 2,
          prefixIcon: const Icon(
            Symbols.calendar_month,
            color: AppColors.primaryDark,
          ),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  onPressed: onClear,
                  tooltip: clearTooltip,
                  icon: const Icon(Symbols.close),
                ),
        ),
        child: Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
