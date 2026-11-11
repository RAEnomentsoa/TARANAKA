import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/i18n/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/status_pill.dart';

/// Scans the QR code shown by a beneficiary ("Mon code") and returns its
/// text. Without camera (refused, none), the code can still be typed.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _detect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final value = b.rawValue;
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.agentScanQr)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(l10n.agentScanHint, style: Theme.of(context).textTheme.bodyLarge),
            ),
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _detect,
                errorBuilder: (context, error) => Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: NoticeBox(
                    icon: Icons.no_photography_outlined,
                    tone: Tone.warning,
                    text: l10n.agentScanNoCamera,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
