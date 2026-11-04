import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/growth/who_lms.dart';
import '../../../core/theme/tokens.dart';
import '../data/child_repository.dart';

/// Weight-for-age chart. The WHO curves (−3, −2, median, +2, +3 SD) are drawn
/// only from the official table when it is bundled; otherwise only the
/// child's own points are shown.
class GrowthChart extends StatelessWidget {
  const GrowthChart({
    super.key,
    required this.entries,
    required this.tables,
    required this.sex,
    required this.semanticLabel,
  });

  final List<GrowthEntry> entries;
  final WhoTables tables;
  final String sex;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    image: true,
    child: AspectRatio(
      aspectRatio: 1.4,
      child: CustomPaint(
        painter: _GrowthPainter(entries, tables, sex, Theme.of(context).textTheme.bodySmall!),
      ),
    ),
  );
}

class _GrowthPainter extends CustomPainter {
  _GrowthPainter(this.entries, this.tables, this.sex, this.labelStyle);

  final List<GrowthEntry> entries;
  final WhoTables tables;
  final String sex;
  final TextStyle labelStyle;

  static const double _daysPerMonth = 30.4375;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 32.0, bottom = 22.0, top = 8.0, right = 8.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final maxMonths = math
        .max(12, ((entries.isEmpty ? 0 : entries.last.ageDays / _daysPerMonth) / 6).ceil() * 6)
        .toDouble();

    final curves = <double, List<Offset>>{};
    if (tables.has(WhoIndicator.wfa)) {
      for (final z in const [-3.0, -2.0, 0.0, 2.0, 3.0]) {
        final pts = <Offset>[];
        for (var d = 0; d <= maxMonths * _daysPerMonth; d += 15) {
          final lms = tables.lookup(WhoIndicator.wfa, sex, d);
          if (lms != null) pts.add(Offset(d / _daysPerMonth, WhoLms.valueAt(lms.l, lms.m, lms.s, z)));
        }
        curves[z] = pts;
      }
    }
    final ys = [for (final e in entries) e.weightKg, for (final c in curves.values) ...c.map((o) => o.dy)];
    final maxKg = ys.isEmpty ? 12.0 : (ys.reduce(math.max) / 2).ceil() * 2.0 + 1;

    Offset at(double months, double kg) =>
        Offset(plot.left + months / maxMonths * plot.width, plot.bottom - kg / maxKg * plot.height);

    final grid = Paint()
      ..color = AppColors.accentSoftBorder
      ..strokeWidth = 1;
    for (var m = 0.0; m <= maxMonths; m += 3) {
      canvas.drawLine(at(m, 0), at(m, maxKg), grid);
      _label(canvas, '${m.toInt()}', at(m, 0) + const Offset(-4, 4));
    }
    for (var kg = 0.0; kg <= maxKg; kg += 2) {
      canvas.drawLine(at(0, kg), at(maxMonths, kg), grid);
      _label(canvas, '${kg.toInt()}', at(0, kg) + const Offset(-26, -7));
    }

    for (final e in curves.entries) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.key == 0 ? 2 : 1.2
        ..color = e.key.abs() == 3 ? AppColors.danger : (e.key == 0 ? AppColors.success : AppColors.warning);
      final path = Path();
      for (var i = 0; i < e.value.length; i++) {
        final p = at(e.value[i].dx, e.value[i].dy);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }

    final line = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = AppColors.accent;
    final path = Path();
    for (var i = 0; i < entries.length; i++) {
      final p = at(entries[i].ageDays / _daysPerMonth, entries[i].weightKg);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      canvas.drawCircle(p, 4.5, dot);
    }
    canvas.drawPath(path, line);
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(color: AppColors.textMuted, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_GrowthPainter old) => old.entries != entries || old.tables != tables;
}
