/// Jours calendaires, représentés en UTC à minuit : les calculs ne sont ainsi
/// jamais décalés par un changement d'heure.
DateTime dayOf(DateTime date) => DateTime.utc(date.year, date.month, date.day);

DateTime addDays(DateTime day, int days) => day.add(Duration(days: days));

int daysBetween(DateTime from, DateTime to) => to.difference(from).inDays;

/// Renvoie `null` si [value] est absente ou illisible.
DateTime? parseDay(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  return parsed == null ? null : dayOf(parsed);
}

/// Format stocké en base : `yyyy-MM-dd`.
String formatDay(DateTime day) => day.toIso8601String().substring(0, 10);
