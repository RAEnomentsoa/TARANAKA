import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/platform/file_saver.dart';
import '../../../core/security/pin_crypto.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';
import '../../../core/widgets/status_pill.dart';

/// The 6 recovery codes together in one block: one copy icon for all of them
/// (top right) and one "Télécharger" button under the block (a text file
/// saved where the user chooses). Each code works alone.
/// [onSaved] is called once the codes were downloaded or copied.
class RecoveryCodeCard extends StatefulWidget {
  const RecoveryCodeCard({super.key, required this.code, this.profileName, this.onSaved});

  /// The codes as stored ("ABCD EFGH …").
  final String code;
  final String? profileName;
  final VoidCallback? onSaved;

  @override
  State<RecoveryCodeCard> createState() => _RecoveryCodeCardState();
}

class _RecoveryCodeCardState extends State<RecoveryCodeCard> {
  String? _done;
  bool _failed = false;

  List<String> get _codes => PinCrypto.splitRecoveryCodes(widget.code);

  /// One code per line: easy to read back and to paste.
  String get _plain => _codes.join('\n');

  Future<void> _download() async {
    final l10n = context.l10n;
    final text = [
      l10n.recoveryCodeFileTitle,
      if (widget.profileName != null) l10n.recoveryCodeFileProfile(widget.profileName!),
      '',
      for (final (i, c) in _codes.indexed) '${i + 1}. $c',
      '',
      l10n.recoveryCodeFileHelp,
    ].join('\n');
    final ok = await TextFileSaver.save(fileName: 'taranaka-codes-recuperation.txt', text: text);
    if (!mounted) return;
    setState(() {
      _failed = !ok;
      _done = ok ? l10n.recoveryCodeDownloaded : null;
    });
    if (ok) widget.onSaved?.call();
  }

  Future<void> _copy() async {
    final l10n = context.l10n;
    await Clipboard.setData(ClipboardData(text: _plain));
    if (!mounted) return;
    setState(() {
      _failed = false;
      _done = l10n.recoveryCodeCopied;
    });
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final codes = _codes;
    final codeStyle = text.titleLarge?.copyWith(
      fontFamily: 'monospace',
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('recovery-codes-block'),
          padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.xs, Space.m),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(Radii.m),
            border: Border.all(color: AppColors.accentSoftBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.recoveryCodesLabel(codes.length),
                      style: text.labelLarge?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('recovery-code-copy'),
                    tooltip: l10n.recoveryCodeCopy,
                    onPressed: _copy,
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
              // Two columns of 3 (one column when the text is very large).
              LayoutBuilder(
                builder: (context, box) {
                  final perRow = box.maxWidth >= 220 ? 2 : 1;
                  final width = (box.maxWidth - Space.s * (perRow - 1) - Space.s) / perRow;
                  return Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      for (final (i, c) in codes.indexed)
                        SizedBox(
                          width: width,
                          child: Semantics(
                            label: '${i + 1} : ${c.split('').join(' ')}',
                            child: ExcludeSemantics(
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${i + 1}.',
                                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                                    ),
                                  ),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(c, key: ValueKey('recovery-code-$i'), style: codeStyle),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const Gap(Space.m),
        FilledButton.tonalIcon(
          key: const ValueKey('recovery-code-download'),
          onPressed: _download,
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.recoveryCodeDownload),
        ),
        if (_done != null) ...[
          const Gap(Space.s),
          NoticeBox(icon: Icons.check_circle_outline, tone: Tone.success, text: _done!),
        ] else if (_failed) ...[
          const Gap(Space.s),
          NoticeBox(icon: Icons.edit_note, tone: Tone.caution, text: l10n.recoveryCodeDownloadFailed),
        ],
        const Gap(Space.s),
        Text(l10n.recoveryCodeWarning, style: text.bodySmall),
      ],
    );
  }
}
