import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/alerts/alert_contact.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_pill.dart';
import '../data/child_repository.dart';
import '../domain/vaccines.dart';
import 'my_children_screen.dart';
import 'vaccines_screen.dart';

/// Records a dose as on the vaccination card: real date, health centre,
/// professional, and whether the card confirms it. Also corrects or deletes
/// a dose already recorded. The other doses still to give on the same visit
/// can be ticked to record them together. Pops `true` after a change.
class VaccineRecordScreen extends StatefulWidget {
  const VaccineRecordScreen({super.key, required this.child, required this.dose, required this.all});

  final MyChild child;
  final VaccineDose dose;
  final List<VaccineDose> all;

  @override
  State<VaccineRecordScreen> createState() => _VaccineRecordScreenState();
}

class _VaccineRecordScreenState extends State<VaccineRecordScreen> {
  DateTime? _date;
  final _centre = TextEditingController();
  final _professional = TextEditingController();
  bool? _confirmed;
  final _together = <String>{};
  bool _saving = false;

  bool get _editing => widget.dose.record != null;

  /// Doses not yet received with the same planned date (same visit).
  List<VaccineDose> get _sameVisit => _editing
      ? const []
      : widget.all
            .where(
              (d) =>
                  d.code != widget.dose.code &&
                  d.dueDate == widget.dose.dueDate &&
                  d.status != DoseStatus.done &&
                  d.status != DoseStatus.expired,
            )
            .toList();

  @override
  void initState() {
    super.initState();
    final r = widget.dose.record;
    if (r != null) {
      _date = r.date;
      _centre.text = r.centre;
      _professional.text = r.professional;
      _confirmed = r.confirmedByCard;
    } else {
      _together.addAll(_sameVisit.map((d) => d.code));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_editing && _centre.text.isEmpty) _prefillCentre();
  }

  Future<void> _prefillCentre() async {
    final db = AppScope.read(context).session.active?.db;
    if (db == null) return;
    final contact = await AlertContact.load(db);
    if (mounted && _centre.text.isEmpty) _centre.text = contact.centreName;
  }

  @override
  void dispose() {
    _centre.dispose();
    _professional.dispose();
    super.dispose();
  }

  String _issueText(AppLocalizations l10n, DoseDateIssue i, VaccineDose dose) => switch (i) {
    DoseDateIssue.beforeBirth => l10n.vaccineDateBeforeBirth,
    DoseDateIssue.inFuture => l10n.vaccineDateInFuture,
    DoseDateIssue.beforeMinAge => l10n.vaccineDateTooEarly(formatDate(dose.dueDate)),
    DoseDateIssue.tooSoonAfterPrevious => l10n.vaccineDateTooSoon(dose.minIntervalDays ~/ 7),
    DoseDateIssue.afterLastDay => l10n.vaccineDateAfterLimit,
  };

  Future<void> _save() async {
    final l10n = context.l10n;
    final date = _date;
    // The wheel stops at today: a dose received cannot be in the future.
    if (date == null || dateOnly(date).isAfter(dateOnly(AppScope.read(context).services.clock.now()))) return;
    final now = AppScope.read(context).services.clock.now();
    final codes = [widget.dose.code, ..._together];
    final doses = widget.all.where((d) => codes.contains(d.code)).toList();
    final problems = <String>{
      for (final d in doses)
        for (final i in VaccineSchedule.checkDate(
          d,
          date,
          birthDate: widget.child.birthDate,
          today: now,
          all: widget.all,
        ))
          if (i != DoseDateIssue.inFuture) '${d.name} : ${_issueText(l10n, i, d)}',
    };
    if (problems.isNotEmpty) {
      final go = await confirmAction(
        context,
        message: '${l10n.vaccineDateCheck}\n\n${problems.join('\n')}',
        confirmLabel: l10n.vaccineSaveAnyway,
      );
      if (!go) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final repo = childRepository(context);
    for (final d in doses) {
      await repo.saveVaccine(
        widget.child.id,
        VaccineRecord(
          code: d.code,
          date: dateOnly(date),
          centre: _centre.text.trim(),
          professional: _professional.text.trim(),
          confirmedByCard: _confirmed,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await confirmAction(
      context,
      message: l10n.vaccineDeleteConfirm(widget.dose.name),
      confirmLabel: l10n.vaccineDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await childRepository(context).unmarkVaccine(widget.child.id, widget.dose.code);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final d = widget.dose;
    final now = AppScope.of(context).services.clock.now();
    final birth = dateOnly(widget.child.birthDate);
    final today = dateOnly(now);
    final sameVisit = _sameVisit;
    return AppScreen(
      title: _editing ? l10n.vaccineEditTitle : l10n.vaccineRecordTitle,
      bottomAction: FilledButton.icon(
        key: const ValueKey('vaccine-save'),
        onPressed: _date == null || _saving ? null : _save,
        icon: const Icon(Icons.check),
        label: Text(l10n.vaccineSave),
      ),
      children: [
        Text(d.name, style: text.titleLarge),
        if (d.protects.isNotEmpty)
          Text(d.protects, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
        if (d.route.isNotEmpty) Text(d.route, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        const Gap(Space.s),
        vaccineStatusPill(context, d),
        if (!_editing) ...[
          const Gap(Space.xs),
          Text(l10n.vaccinePlannedOn(formatDate(d.dueDate)), style: text.bodySmall),
        ],
        const Gap(Space.l),
        DateField(
          key: const ValueKey('vaccine-date'),
          label: l10n.vaccineRealDate,
          value: _date,
          initial: today.isBefore(d.dueDate) ? today : (d.dueDate.isBefore(birth) ? birth : d.dueDate),
          first: birth,
          last: today,
          onChanged: (v) => setState(() => _date = v),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('vaccine-centre'),
          controller: _centre,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.vaccineCentre,
            prefixIcon: const Icon(Icons.local_hospital_outlined),
          ),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('vaccine-professional'),
          controller: _professional,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.vaccineProfessional,
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const Gap(Space.l),
        Text(l10n.vaccineCardQuestion, style: text.titleSmall),
        const Gap(Space.xs),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            ChoiceChip(
              key: const ValueKey('vaccine-card-yes'),
              avatar: const Icon(Icons.fact_check_outlined, size: 18),
              label: Text(l10n.yes),
              selected: _confirmed == true,
              onSelected: (s) => setState(() => _confirmed = s ? true : null),
            ),
            ChoiceChip(
              key: const ValueKey('vaccine-card-no'),
              avatar: const Icon(Icons.help_outline, size: 18),
              label: Text(l10n.no),
              selected: _confirmed == false,
              onSelected: (s) => setState(() => _confirmed = s ? false : null),
            ),
          ],
        ),
        if (_confirmed == false) ...[const Gap(Space.s), NoticeBox.tip(text: l10n.vaccineCardNoTip)],
        if (sameVisit.isNotEmpty) ...[
          const Gap(Space.l),
          Text(l10n.vaccineSameVisit, style: text.titleSmall),
          for (final o in sameVisit)
            CheckboxListTile(
              key: ValueKey('vaccine-together-${o.code}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _together.contains(o.code),
              title: Text(o.name),
              subtitle: o.protects.isEmpty ? null : Text(o.protects),
              onChanged: (v) => setState(() => v == true ? _together.add(o.code) : _together.remove(o.code)),
            ),
        ],
        if (_editing) ...[
          const Gap(Space.xl),
          OutlinedButton.icon(
            key: const ValueKey('vaccine-delete'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(l10n.vaccineDelete),
          ),
        ],
      ],
    );
  }
}
