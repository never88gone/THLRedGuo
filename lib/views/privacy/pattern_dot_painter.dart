import 'package:flutter/material.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class PatternDotPainter extends CustomPainter {
  const PatternDotPainter({
    required this.selectedDots,
    required this.dotCenters,
    required this.isError,
    required this.isDark,
    this.currentTouchPoint,
  });

  final List<int> selectedDots;
  final Map<int, Offset> dotCenters;
  final Offset? currentTouchPoint;
  final bool isError;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    _drawLines(canvas);
    _drawDots(canvas);
  }

  void _drawLines(Canvas canvas) {
    if (selectedDots.isEmpty) return;

    final lineColor = isError
        ? AppColors.patternLineError
        : AppColors.patternLineActive;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final firstCenter = dotCenters[selectedDots.first];
    if (firstCenter != null) {
      path.moveTo(firstCenter.dx, firstCenter.dy);
      for (var i = 1; i < selectedDots.length; i++) {
        final point = dotCenters[selectedDots[i]];
        if (point != null) {
          path.lineTo(point.dx, point.dy);
        }
      }

      if (currentTouchPoint != null && !isError) {
        path.lineTo(currentTouchPoint!.dx, currentTouchPoint!.dy);
      }

      canvas.drawPath(path, linePaint);
    }
  }

  void _drawDots(Canvas canvas) {
    final normalDotColor = isDark
        ? AppColors.patternDotNormalDark
        : AppColors.patternDotNormal;
    final activeDotColor = isError
        ? AppColors.patternDotError
        : AppColors.patternDotActive;
    final activeHaloColor = isError
        ? AppColors.patternHaloError
        : AppColors.patternHaloActive;

    final normalPaint = Paint()
      ..color = normalDotColor
      ..style = PaintingStyle.fill;

    final ringPaint = Paint()
      ..color = AppColors.patternDotRing
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final activePaint = Paint()
      ..color = activeDotColor
      ..style = PaintingStyle.fill;

    final haloPaint = Paint()
      ..color = activeHaloColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 9; i++) {
      final center = dotCenters[i];
      if (center == null) continue;

      final isSelected = selectedDots.contains(i);
      if (isSelected) {
        canvas.drawCircle(center, 28, haloPaint);
        canvas.drawCircle(center, 28, Paint()
          ..color = activeDotColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
        canvas.drawCircle(center, 8, activePaint);
      } else {
        canvas.drawCircle(center, 24, ringPaint);
        canvas.drawCircle(center, 6, normalPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PatternDotPainter oldDelegate) {
    return oldDelegate.selectedDots != selectedDots ||
        oldDelegate.currentTouchPoint != currentTouchPoint ||
        oldDelegate.isError != isError ||
        oldDelegate.isDark != isDark;
  }
}
