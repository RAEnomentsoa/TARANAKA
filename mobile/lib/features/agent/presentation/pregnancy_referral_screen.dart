import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/config/clinical_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/util/clock.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/models.dart';
import 'agent_scope.dart';
import 'centre_picker.dart';
import 'referral_sheet_screen.dart';

/// The agent refers a pregnant woman for danger signs (D16, `origine:
/// grossesse`): the signs seen, then the centre. Works offline: the signs and
/// the referral are sent with the next sync. Without a pregnancy on record,
/// its date (last period or due date) is asked first.
class PregnancyReferralScreen extends StatefulWidget {
  const PregnancyReferralScreen({super.key, required this.mother, this.pregnancy});

  final Beneficiary mother;
  final AgentPregnancy? pregnancy;

  @override
  State<PregnancyReferralScreen> createState() => _PregnancyReferralScreenState();
}

class _PregnancyReferralScreenState extends State<PregnancyReferralScreen> {
  final _signs = <String>{};
  DateTime? _lmp;
  DateTime? _due;
  String? _error;
  bool _busy = false;

  Future<void> _refer(List<Map<String, Object?>> all) async {
    final l10n = context.l10n;
    if (widget.pregnancy == null && _lmp == null && _due == null) {
      return setState(() => _error = l10n.referPregnancyDates);
    }
    if (_signs.isEmpty) return setState(() => _error = l10n.selectAtLeastOneSign);
    final agent = AgentScope.read(context);
    final lang = context.lang;
    final centre = await pickCentre(context, preferredType: 'csb');
    if (centre == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final user = agent.account!.user;
    final pregnancy =
        widget.pregnancy ??
        await agent.repo.createPregnancy(userId: widget.mother.id, lmp: _lmp, dueDate: _due);
    final labels = {for (final s in all) s['code']: localizedText(s, lang)};
    final referral = await agent.repo.createPregnancyReferral(
      pregnancy: pregnancy,
      signs: _signs.toList(),
      centre: centre,
      motif: [for (final c in _signs) labels[c] ?? c].join(', '),
      agentId: user.id,
    );
    await agent.refreshCounts();
    if (!mounted) return;
    await pushAgent<void>(context, ReferralSheetScreen(referralId: referral.id), replace: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final config = AppScope.of(context).services.config.current;
    final today = dateOnly(AppScope.of(context).services.clock.now());
    final all = asMapList(config.signesDanger['grossesse']);
    final name = widget.mother.displayName.isEmpty ? (widget.mother.code ?? '') : widget.mother.displayName;
    return AppScreen(
      title: l10n.referPregnancyTitle,
      bottomAction: FilledButton.icon(
        key: const ValueKey('pregnancy-refer'),
        onPressed: _busy ? null : () => _refer(all),
        icon: const Icon(Icons.assignment_late_outlined),
        label: Text(l10n.referPregnancySend),
      ),
      children: [
        NoticeBox(icon: Icons.woman, tone: Tone.info, text: l10n.childFormMother(name)),
        const Gap(Space.l),
        if (_error != null) ...[
          NoticeBox(
            key: const ValueKey('pregnancy-refer-error'),
            icon: Icons.error_outline,
            tone: Tone.danger,
            text: _error!,
          ),
          const Gap(Space.l),
        ],
        if (widget.pregnancy == null) ...[
          Text(l10n.referPregnancyDates),
          const Gap(Space.m),
          DateField(
            key: const ValueKey('pregnancy-lmp'),
            label: l10n.referPregnancyLmp,
            value: _lmp,
            first: addDays(today, -300),
            last: today,
            onChanged: (d) => setState(() => _lmp = d),
          ),
          const Gap(Space.m),
          DateField(
            key: const ValueKey('pregnancy-due'),
            label: l10n.referPregnancyDue,
            value: _due,
            first: addDays(today, -60),
            last: addDays(today, 300),
            onChanged: (d) => setState(() => _due = d),
          ),
          const Gap(Space.l),
        ],
        Text(l10n.referPregnancySigns, style: Theme.of(context).textTheme.titleMedium),
        const Gap(Space.s),
        Card(
          child: Column(
            children: [
              for (final s in all)
                if (s['code'] is String)
                  CheckboxListTile(
                    key: ValueKey('sign-${s['code']}'),
                    value: _signs.contains(s['code']),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(localizedText(s, lang)),
                    onChanged: (v) => setState(() {
                      final code = s['code']! as String;
                      v == true ? _signs.add(code) : _signs.remove(code);
                    }),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}
