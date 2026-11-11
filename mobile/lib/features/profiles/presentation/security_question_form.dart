import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/security/security_question.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/theme/tokens.dart';

/// Secret question written freely by the user, and its answer, each typed
/// once. Errors are shown under the field concerned. Read it with
/// [SecurityQuestionFormState.validate]; [onSubmitted] runs when "OK" is
/// pressed on the keyboard in the answer field.
class SecurityQuestionForm extends StatefulWidget {
  const SecurityQuestionForm({super.key, this.initial, this.onSubmitted, this.showAnswerHelp = true});

  /// Filled again when coming back to this step.
  final ({String question, String answer})? initial;

  final VoidCallback? onSubmitted;

  /// The remark under the answer ("Les majuscules et les espaces…").
  final bool showAnswerHelp;

  @override
  State<SecurityQuestionForm> createState() => SecurityQuestionFormState();
}

class SecurityQuestionFormState extends State<SecurityQuestionForm> {
  final _question = TextEditingController();
  final _answer = TextEditingController();
  final _answerFocus = FocusNode();

  /// Shown by default: typed only once, the answer must be checked by eye.
  bool _hidden = false;
  String? _questionError;
  String? _answerError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _question.text = initial.question;
      _answer.text = initial.answer;
    }
  }

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  /// The question and the answer, or null with the errors shown.
  ({String question, String answer})? validate() {
    final l10n = context.l10n;
    setState(() {
      _questionError = SecurityQuestion.validQuestion(_question.text) ? null : l10n.secretQuestionRequired;
      _answerError = SecurityQuestion.validAnswer(_answer.text) ? null : l10n.secretAnswerTooShort;
    });
    if (_questionError != null || _answerError != null) return null;
    return (question: _question.text.trim(), answer: _answer.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('secret-question'),
          controller: _question,
          textCapitalization: TextCapitalization.sentences,
          maxLength: SecurityQuestion.maxQuestionLength,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _answerFocus.requestFocus(),
          onChanged: (_) {
            if (_questionError != null) setState(() => _questionError = null);
          },
          decoration: InputDecoration(
            labelText: l10n.secretQuestionLabel,
            errorText: _questionError,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.help_outline),
          ),
        ),
        const Gap(Space.s),
        TextField(
          key: const ValueKey('secret-answer'),
          controller: _answer,
          focusNode: _answerFocus,
          obscureText: _hidden,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: SecurityQuestion.maxAnswerLength,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          onChanged: (_) {
            if (_answerError != null) setState(() => _answerError = null);
          },
          decoration: InputDecoration(
            labelText: l10n.secretAnswerLabel,
            helperText: widget.showAnswerHelp ? l10n.secretAnswerHelp : null,
            helperMaxLines: 4,
            errorText: _answerError,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.key_outlined),
            suffixIcon: IconButton(
              key: const ValueKey('secret-answer-toggle'),
              tooltip: _hidden ? l10n.secretAnswerShow : l10n.secretAnswerHide,
              icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _hidden = !_hidden),
            ),
          ),
        ),
      ],
    );
  }
}
