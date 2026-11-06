import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../cores/services/cycle_timeline.dart';
import '../../cores/themes/app_colors.dart';
import 'phase_style.dart';

/// Roue du cycle : un segment par jour, coloré selon la phase et portant le
/// numéro du jour dans le mois. Le texte de la roue suit sa géométrie et non le
/// réglage de taille du système ; [semanticLabel] en donne l'équivalent complet.
class CycleWheel extends StatelessWidget {
  const CycleWheel({
    super.key,
    required this.days,
    required this.todayIndex,
    required this.semanticLabel,
    required this.center,
  });

  /// Vide tant qu'aucun cycle n'est enregistré : l'anneau reste alors neutre.
  final List<(DateTime, CyclePhase)> days;

  /// Position du jour courant dans [days], `null` s'il n'y figure pas.
  final int? todayIndex;
  final String semanticLabel;
  final Widget center;

  static const double _maxDiameter = 340;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = min(constraints.maxWidth, _maxDiameter);
        final geometry = _WheelGeometry(diameter);
        final hole = geometry.innerRadius * sqrt2;
        return Center(
          child: Semantics(
            container: true,
            image: true,
            label: semanticLabel,
            child: ExcludeSemantics(
              child: SizedBox.square(
                dimension: diameter,
                child: CustomPaint(
                  painter: _WheelPainter(days, todayIndex),
                  child: Center(
                    child: SizedBox.square(
                      dimension: hole,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: hole),
                          child: center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WheelGeometry {
  _WheelGeometry(double diameter)
    : outerRadius = diameter / 2 - _pointerSpace,
      ringWidth = (diameter / 2 - _pointerSpace) * 0.2;

  /// Réserve autour de l'anneau pour le repère du jour courant.
  static const double _pointerSpace = 14;

  final double outerRadius;
  final double ringWidth;

  double get innerRadius => outerRadius - ringWidth;
  double get middleRadius => outerRadius - ringWidth / 2;
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.days, this.todayIndex);

  final List<(DateTime, CyclePhase)> days;
  final int? todayIndex;

  static const double _top = -pi / 2;
  static const double _gap = 0.012;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _WheelGeometry(size.width);
    final center = size.center(Offset.zero);
    final middle = Rect.fromCircle(
      center: center,
      radius: geometry.middleRadius,
    );
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = geometry.ringWidth;

    if (days.isEmpty) {
      canvas.drawCircle(
        center,
        geometry.middleRadius,
        stroke..color = const Color(0xFFE0E4E8),
      );
      return;
    }

    final sweep = 2 * pi / days.length;
    for (var i = 0; i < days.length; i++) {
      canvas.drawArc(
        middle,
        _top + i * sweep + _gap / 2,
        sweep - _gap,
        false,
        stroke..color = days[i].$2.color,
      );
    }
    _paintLabels(canvas, center, geometry, sweep);

    final today = todayIndex;
    if (today != null) _paintTodayMark(canvas, center, geometry, sweep, today);
  }

  void _paintLabels(
    Canvas canvas,
    Offset center,
    _WheelGeometry geometry,
    double sweep,
  ) {
    final segmentWidth = sweep * geometry.middleRadius;
    final fontSize = (segmentWidth * 0.55).clamp(9.0, 13.0);
    // Sur un très long cycle, un jour sur [step] seulement reste lisible.
    final step = (fontSize * 1.25 / segmentWidth).ceil();

    for (var i = 0; i < days.length; i++) {
      if (i % step != 0 && i != todayIndex) continue;
      final (date, phase) = days[i];
      final painter = TextPainter(
        text: TextSpan(
          text: '${date.day}',
          style: TextStyle(
            color: phase.onColor,
            fontSize: fontSize,
            fontWeight: i == todayIndex ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final angle = _top + (i + 0.5) * sweep;
      final position =
          center + Offset.fromDirection(angle, geometry.middleRadius);
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
      painter.dispose();
    }
  }

  void _paintTodayMark(
    Canvas canvas,
    Offset center,
    _WheelGeometry geometry,
    double sweep,
    int today,
  ) {
    final ink = Paint()..color = AppColors.ink;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: geometry.outerRadius + 2),
      _top + today * sweep,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.ink,
    );

    final angle = _top + (today + 0.5) * sweep;
    final tip = center + Offset.fromDirection(angle, geometry.outerRadius + 4);
    final base = geometry.outerRadius + 14;
    final side = 7 / base;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          center.dx + base * cos(angle - side),
          center.dy + base * sin(angle - side),
        )
        ..lineTo(
          center.dx + base * cos(angle + side),
          center.dy + base * sin(angle + side),
        )
        ..close(),
      ink,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.todayIndex != todayIndex ||
      !listEquals(oldDelegate.days, days);
}
