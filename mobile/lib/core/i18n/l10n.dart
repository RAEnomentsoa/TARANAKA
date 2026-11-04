import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import '../util/clock.dart';

export '../../l10n/gen/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get lang => Localizations.localeOf(this).languageCode;
}

/// Numeric dates (dd/MM/yyyy) read the same in French and Malagasy and need
/// no month names (intl has no Malagasy date symbols).
String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String formatDateTime(DateTime d) {
  final local = d.toLocal();
  return '${formatDate(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Decimal with a comma in French and Malagasy ("8,6 kg").
String formatDecimal(num value, {int digits = 1}) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');

/// Parses "8,6" or "8.6".
double? parseDecimal(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

String isoDay(DateTime d) => isoDate(d);
