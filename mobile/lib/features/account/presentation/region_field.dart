import 'package:flutter/material.dart';

import '../../../core/i18n/l10n.dart';
import '../domain/regions.dart';

/// "Votre région" (D16): chosen when the profile is created, so the health
/// staff of her zone can follow her. Works offline (bundled list).
class RegionField extends StatelessWidget {
  const RegionField({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<String>(
      key: const ValueKey('region-field'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.regionLabel, prefixIcon: const Icon(Icons.place_outlined)),
      items: [
        for (final r in madagascarRegions)
          DropdownMenuItem(
            value: r,
            key: ValueKey('region-$r'),
            child: Text(r, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
