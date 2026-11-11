import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/screen.dart';

/// "Écouter" the consent in Malagasy or French (D16, low literacy). The
/// recordings are bundled (assets/audio/, offline); a missing one leaves its
/// button disabled, with "Audio bientôt disponible".
class ConsentAudio extends StatefulWidget {
  const ConsentAudio({super.key});

  static String asset(String lang) => 'audio/consentement_$lang.mp3';

  @override
  State<ConsentAudio> createState() => _ConsentAudioState();
}

class _ConsentAudioState extends State<ConsentAudio> {
  AudioPlayer? _player;
  String? _playing;
  late final Future<Set<String>> _available = _find();

  static Future<Set<String>> _find() async {
    final found = <String>{};
    for (final lang in const ['mg', 'fr']) {
      try {
        await rootBundle.load('assets/${ConsentAudio.asset(lang)}');
        found.add(lang);
      } on Object {
        // Not recorded yet.
      }
    }
    return found;
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle(String lang) async {
    final player = _player ??= AudioPlayer()
      ..onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = null);
      });
    if (_playing == lang) {
      await player.stop();
      setState(() => _playing = null);
      return;
    }
    await player.stop();
    setState(() => _playing = lang);
    await player.play(AssetSource(ConsentAudio.asset(lang)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<Set<String>>(
      future: _available,
      builder: (context, snap) {
        final available = snap.data ?? const <String>{};
        Widget button(String lang, String label) {
          final playing = _playing == lang;
          return OutlinedButton.icon(
            key: ValueKey('consent-audio-$lang'),
            onPressed: available.contains(lang) ? () => _toggle(lang) : null,
            icon: Icon(playing ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
            label: Text(label),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [button('mg', l10n.consentListenMg), button('fr', l10n.consentListenFr)],
            ),
            if (snap.hasData && available.length < 2) ...[
              const Gap(Space.xs),
              Text(l10n.consentAudioMissing, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        );
      },
    );
  }
}
