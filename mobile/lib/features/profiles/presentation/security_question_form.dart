import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/security/security_question.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';

/// The question in the language of the moment. A question written by hand
/// (older profiles) is shown as it is.
String securityQuestionText(AppLocalizations l10n, String stored) => switch (SecurityQuestion.parse(stored)) {
  SecurityQuestion.firstPet => l10n.secretQuestionFirstPet,
  SecurityQuestion.birthPlace => l10n.secretQuestionBirthPlace,
  SecurityQuestion.primarySchool => l10n.secretQuestionPrimarySchool,
  SecurityQuestion.childhoodNickname => l10n.secretQuestionChildhoodNickname,
  SecurityQuestion.childhoodFriend => l10n.secretQuestionChildhoodFriend,
  SecurityQuestion.favouriteDish => l10n.secretQuestionFavouriteDish,
  null => stored,
};

/// Secret question chosen in a list, with its answer typed twice (a typo
/// here would make the recovery impossible later). Errors are shown under
/// the field concerned. Read it with [SecurityQuestionFormState.validate].
class SecurityQuestionForm extends StatefulWidget {
  const SecurityQuestionForm({super.key, this.initial});

  /// Filled again when coming back to this step.
  final ({String question, String answer})? initial;

  @override
  State<SecurityQuestionForm> createState() => SecurityQuestionFormState();
}

class SecurityQuestionFormState extends State<SecurityQuestionForm> {
  final _answer = TextEditingController();
  final _confirm = TextEditingController();
  SecurityQuestion? _question;
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _question = SecurityQuestion.parse(initial.question);
      _answer.text = initial.answer;
      _confirm.text = initial.answer;
    }
  }

  String? _questionError;
  String? _answerError;
  String? _confirmError;

  @override
  void dispose() {
    _answer.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// The question (as kept by the profile) and the answer, or null with the
  /// errors shown.
  ({String question, String answer})? validate() {
    final l10n = context.l10n;
    setState(() {
      _questionError = _question == null ? l10n.secretQuestionRequired : null;
      _answerError = SecurityQuestion.validAnswer(_answer.text) ? null : l10n.secretAnswerTooShort;
      _confirmError = _answerError == null && !SecurityQuestion.sameAnswer(_answer.text, _confirm.text)
          ? l10n.secretAnswerMismatch
          : null;
    });
    if (_questionError != null || _answerError != null || _confirmError != null) return null;
    return (question: _question!.stored, answer: _answer.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final toggle = IconButton(
      key: const ValueKey('secret-answer-toggle'),
      tooltip: _hidden ? l10n.secretAnswerShow : l10n.secretAnswerHide,
      icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _hidden = !_hidden),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<SecurityQuestion>(
          key: const ValueKey('secret-question'),
          initialValue: _question,
          isExpanded: true,
          itemHeight: null,
          decoration: InputDecoration(
            labelText: l10n.secretQuestionLabel,
            hintText: l10n.secretQuestionPick,
            errorText: _questionError,
            prefixIcon: const Icon(Icons.help_outline),
          ),
          // The chosen question may need two lines (long text, 200 %).
          selectedItemBuilder: (context) => [
            for (final q in SecurityQuestion.values)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  securityQuestionText(l10n, q.stored),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          items: [
            for (final q in SecurityQuestion.values)
              DropdownMenuItem(
                key: ValueKey('secret-question-${q.name}'),
                value: q,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s),
                  child: Text(securityQuestionText(l10n, q.stored)),
                ),
              ),
          ],
          onChanged: (q) => setState(() {
            _question = q;
            _questionError = null;
          }),
        ),
        const Gap(Space.m),
        TextField(
          key: const ValueKey('secret-answer'),
          controller: _answer,
          obscureText: _hidden,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 60,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.secretAnswerLabel,
            helperText: l10n.secretAnswerHelp,
            helperMaxLines: 4,
            errorText: _answerError,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.key_outlined),
            suffixIcon: toggle,
          ),
        ),
        const Gap(Space.s),
        TextField(
          key: const ValueKey('secret-answer-confirm'),
          controller: _confirm,
          obscureText: _hidden,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 60,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.secretAnswerConfirm,
            errorText: _confirmError,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.key_outlined),
          ),
        ),
      ],
    );
  }
}
