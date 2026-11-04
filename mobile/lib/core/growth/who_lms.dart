import 'dart:math' as math;

/// WHO 2006 Child Growth Standards: z-scores from the LMS method.
///
/// This file is the WHO formula only. The LMS values are data, read from the
/// official tables (assets/who/, see [WhoTables]); none is written here.
abstract final class WhoLms {
  /// z = ((y/M)^L − 1) / (L·S), or ln(y/M)/S when L = 0. For weight-based
  /// indicators WHO restricts the tails: beyond ±3 SD the distance is measured
  /// in units of the 2→3 SD interval ([restricted] = true), as in the server
  /// (`Backend_serveur/nutrition/zscores.py`).
  static double zscore(double y, double l, double m, double s, {bool restricted = false}) {
    var z = l == 0 ? math.log(y / m) / s : (math.pow(y / m, l) - 1) / (l * s);
    if (restricted && z.abs() > 3) {
      final sd3 = valueAt(l, m, s, z > 0 ? 3 : -3);
      final sd2 = valueAt(l, m, s, z > 0 ? 2 : -2);
      z = z > 0 ? 3 + (y - sd3) / (sd3 - sd2) : -3 + (y - sd3) / (sd2 - sd3);
    }
    return z;
  }

  /// The measurement at z standard deviations (WHO's SD curves).
  static double valueAt(double l, double m, double s, double z) =>
      l == 0 ? m * math.exp(s * z) : m * math.pow(1 + l * s * z, 1 / l).toDouble();

  /// Rounded to 2 decimals exactly like the server
  /// (`Decimal(str(z)).quantize(Decimal("0.01"), ROUND_HALF_UP)`): on the
  /// shortest decimal form of the number, half away from zero; never -0.00.
  static double round2(double z) {
    final text = z.abs().toString();
    if (text.contains('e') || !z.isFinite) {
      final r = (z.abs() * 100 + 0.5).floorToDouble() / 100 * z.sign;
      return r == 0 ? 0 : r;
    }
    final parts = text.split('.');
    final frac = (parts.length > 1 ? parts[1] : '').padRight(3, '0');
    var cents = BigInt.parse(parts[0]) * BigInt.from(100) + BigInt.parse(frac.substring(0, 2));
    if (frac.codeUnitAt(2) >= 0x35) cents += BigInt.one;
    final r = cents.toDouble() / 100 * z.sign;
    return r == 0 ? 0 : r;
  }
}

enum WhoIndicator {
  /// Weight-for-age, key = age in days.
  wfa('weianthro.txt', 'age', restricted: true),

  /// Length/height-for-age, key = age in days.
  lhfa('lenanthro.txt', 'age', restricted: false),

  /// Weight-for-length (under 731 days), key = length in cm (0.1).
  wfl('wflanthro.txt', 'length', restricted: true),

  /// Weight-for-height (from 731 days), key = height in cm (0.1).
  wfh('wfhanthro.txt', 'height', restricted: true);

  const WhoIndicator(this.fileName, this.keyColumn, {required this.restricted});

  final String fileName;
  final String keyColumn;
  final bool restricted;
}

class Lms {
  const Lms(this.l, this.m, this.s);
  final double l;
  final double m;
  final double s;
}

/// The official WHO tables, as published in the WHO "anthro" package
/// (`data-raw/growthstandards`), parsed from their tab-separated files.
class WhoTables {
  WhoTables(this._rows);

  /// indicator → sex (M/F) → key (days, or tenths of cm) → LMS.
  final Map<WhoIndicator, Map<String, Map<int, Lms>>> _rows;

  bool has(WhoIndicator i) => _rows[i]?.isNotEmpty ?? false;

  Set<WhoIndicator> get loaded => {
    for (final i in WhoIndicator.values)
      if (has(i)) i,
  };

  Lms? lookup(WhoIndicator indicator, String sex, num key) {
    final k = indicator.keyColumn == 'age' ? key.round() : (key * 10).round();
    return _rows[indicator]?[sex]?[k];
  }

  /// Parses one WHO file. Columns are found by name (sex, age|length|height,
  /// l, m, s); sex 1 = M, 2 = F.
  static Map<String, Map<int, Lms>> parse(WhoIndicator indicator, String content) {
    final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const {};
    final header = lines.first.split('\t').map((h) => h.trim().replaceAll('"', '')).toList();
    final iSex = header.indexOf('sex');
    final iKey = header.indexOf(indicator.keyColumn);
    final iL = header.indexOf('l');
    final iM = header.indexOf('m');
    final iS = header.indexOf('s');
    if ([iSex, iKey, iL, iM, iS].contains(-1)) {
      throw FormatException('Unexpected header in ${indicator.fileName}: $header');
    }
    final out = <String, Map<int, Lms>>{'M': {}, 'F': {}};
    for (final line in lines.skip(1)) {
      final c = line.split('\t').map((v) => v.trim().replaceAll('"', '')).toList();
      final sex = switch (c[iSex]) {
        '1' => 'M',
        '2' => 'F',
        _ => null,
      };
      if (sex == null) continue;
      final key = double.parse(c[iKey]);
      final k = indicator.keyColumn == 'age' ? key.round() : (key * 10).round();
      out[sex]![k] = Lms(double.parse(c[iL]), double.parse(c[iM]), double.parse(c[iS]));
    }
    return out;
  }

  static WhoTables fromFiles(Map<WhoIndicator, String> contents) =>
      WhoTables({for (final e in contents.entries) e.key: parse(e.key, e.value)});

  static final WhoTables empty = WhoTables(const {});
}

/// z-scores of one measurement. A field is null when its table is missing or
/// the child is outside it: it is never estimated.
class ZScores {
  const ZScores({this.waz, this.haz, this.whz});
  final double? waz;
  final double? haz;
  final double? whz;

  bool get any => waz != null || haz != null || whz != null;
}

abstract final class GrowthMath {
  static const int maxAgeDays = 1856;

  /// Under 731 days a child is measured lying (length), then standing (height).
  static const int lengthToHeightDays = 731;

  static ZScores compute(
    WhoTables tables, {
    required String sex,
    required int ageDays,
    required double weightKg,
    required double correctedLengthCm,
  }) {
    if (ageDays < 0 || ageDays > maxAgeDays) return const ZScores();
    double? z(WhoIndicator i, num key, double y) {
      final lms = tables.lookup(i, sex, key);
      if (lms == null) return null;
      return WhoLms.round2(WhoLms.zscore(y, lms.l, lms.m, lms.s, restricted: i.restricted));
    }

    final weightForSize = ageDays < lengthToHeightDays ? WhoIndicator.wfl : WhoIndicator.wfh;
    return ZScores(
      waz: z(WhoIndicator.wfa, ageDays, weightKg),
      haz: z(WhoIndicator.lhfa, ageDays, correctedLengthCm),
      whz: z(weightForSize, correctedLengthCm, weightKg),
    );
  }
}
