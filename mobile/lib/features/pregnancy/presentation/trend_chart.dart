import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../domain/follow_up_checks.dart';

/// One line of a [TrendChart]. [square] marks its points with squares
/// instead of dots, so two lines differ by shape too (never colour alone).
class TrendSeries {
  const TrendSeries({required this.label, required this.points, required this.color, this.square = false});

  final String label;
  final List<TrendPoint> points;
  final Color color;
  final bool square;
}

/// A limit drawn as a dashed line (e.g. 140 mmHg), labelled with its value.
class TrendLimit {
  const TrendLimit(this.value, this.color);
  final double value;
  final Color color;
}

/// A simple evolution chart over the weeks of pregnancy (SA): one or two
/// lines, dashed limits, the weeks at the bottom and the values on the left.
/// Light: a CustomPaint, no library. [semanticLabel] says the same in words
/// for TalkBack; the legend under the chart names each line with its shape.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.series,
    required this.semanticLabel,
    required this.weeksLabel,
    this.limits = const [],
    this.step = 5,
  });

  final List<TrendSeries> series;
  final List<TrendLimit> limits;
  final String semanticLabel;

  /// "SA": shown under the weeks.
  final String weeksLabel;

  /// Gap between the value grid lines.
  final double step;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: semanticLabel,
          image: true,
          child: ExcludeSemantics(
            child: AspectRatio(
              aspectRatio: 1.7,
              child: CustomPaint(painter: _TrendPainter(series, limits, step, weeksLabel, small)),
            ),
          ),
        ),
        if (series.length > 1) ...[
          const SizedBox(height: Space.xs),
          ExcludeSemantics(
            child: Wrap(
              spacing: Space.l,
              runSpacing: Space.xs,
              children: [
                for (final s in series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.square ? Icons.square : Icons.circle, size: 12, color: s.color),
                      const SizedBox(width: Space.xs),
                      Text(s.label, style: small),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.series, this.limits, this.step, this.weeksLabel, this.style);

  final List<TrendSeries> series;
  final List<TrendLimit> limits;
  final double step;
  final String weeksLabel;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [for (final s in series) ...s.points];
    if (points.isEmpty) return;
    const left = 34.0, bottom = 30.0, top = 8.0, right = 10.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);

    // Weeks: from the first to the last point, at least 4 weeks wide.
    var minW = points.map((p) => p.weeks).reduce(math.min).floorToDouble();
    var maxW = points.map((p) => p.weeks).reduce(math.max).ceilToDouble();
    if (maxW - minW < 4) {
      minW = math.max(0, minW - 2);
      maxW = minW + 4;
    }
    // Values: the points and the limits, rounded to the grid step.
    final ys = [...points.map((p) => p.value), ...limits.map((l) => l.value)];
    final minV = (ys.reduce(math.min) / step).floor() * step - step;
    final maxV = (ys.reduce(math.max) / step).ceil() * step + step;

    Offset at(double w, double v) => Offset(
      plot.left + (w - minW) / (maxW - minW) * plot.width,
      plot.bottom - (v - minV) / (maxV - minV) * plot.height,
    );

    final grid = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 1;
    // About four value lines, whatever the range.
    final valueStep = math.max(step, (((maxV - minV) / 4) / step).ceil() * step);
    for (var v = minV; v <= maxV + 0.001; v += valueStep) {
      canvas.drawLine(at(minW, v), at(maxW, v), grid);
      _text(canvas, _fmt(v), at(minW, v) + const Offset(-left + 2, -7));
    }
    final weekStep = math.max(1, ((maxW - minW) / 6).ceil());
    for (var w = minW; w <= maxW + 0.001; w += weekStep) {
      _text(canvas, w.toInt().toString(), at(w, minV) + const Offset(-6, 4));
    }
    _text(canvas, weeksLabel, Offset(plot.right - 18, plot.bottom + 15));

    for (final l in limits) {
      final paint = Paint()
        ..color = l.color
        ..strokeWidth = 1.5;
      final a = at(minW, l.value), b = at(maxW, l.value);
      for (var x = a.dx; x < b.dx; x += 8) {
        canvas.drawLine(Offset(x, a.dy), Offset(math.min(x + 4, b.dx), a.dy), paint);
      }
      _text(canvas, _fmt(l.value), Offset(b.dx - 26, a.dy - 15), color: l.color);
    }

    for (final s in series) {
      final pts = [...s.points]..sort((a, b) => a.weeks.compareTo(b.weeks));
      final line = Paint()
        ..color = s.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final dot = Paint()..color = s.color;
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final p = at(pts[i].weeks, pts[i].value);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, line);
      for (final pt in pts) {
        final p = at(pt.weeks, pt.value);
        s.square
            ? canvas.drawRect(Rect.fromCenter(center: p, width: 8, height: 8), dot)
            : canvas.drawCircle(p, 4.5, dot);
      }
    }
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  void _text(Canvas canvas, String text, Offset at, {Color? color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: color ?? AppColors.textMuted, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.series != series || old.limits != limits;
}
