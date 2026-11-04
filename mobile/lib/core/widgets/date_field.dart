import 'package:flutter/material.dart';

import '../i18n/l10n.dart';

/// A date shown as dd/MM/yyyy, picked with the calendar (no typing).
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.first,
    required this.last,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime first;
  final DateTime last;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? last,
          firstDate: first,
          lastDate: last,
          helpText: label,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: const Icon(Icons.edit_calendar_outlined),
        ),
        child: Text(value == null ? context.l10n.chooseDate : formatDate(value!)),
      ),
    );
  }
}
