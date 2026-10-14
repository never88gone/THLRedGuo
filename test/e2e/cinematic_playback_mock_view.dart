import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

class CinematicPlaybackMockView extends StatelessWidget {
  const CinematicPlaybackMockView({
    super.key,
    required this.controls,
    this.badgeText = '红果自制 · 1080P 高清原画',
  });

  final Widget controls;
  final String badgeText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: AppColors.playerSceneDark,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.playerSurface,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.hongguoRedWithAlpha(0.12),
                          blurRadius: 48,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: AppColors.blackWithAlpha(0.9),
                          blurRadius: 32,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            painter: _CinematicPlaybackPainter(),
                          ),
                          Positioned(
                            top: 14,
                            right: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.blackWithAlpha(0.4),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.whiteWithAlpha(0.12)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.hongguoRed,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    badgeText,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.whiteWithAlpha(0.85),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            controls,
          ],
        );
      },
    );
  }
}

class _CinematicPlaybackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.darkSurface,
          AppColors.darkBackground,
          AppColors.playerSceneDark,
          AppColors.black,
        ],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    final silhouettePaint = Paint()..color = AppColors.cinemaSilhouette;
    final path = Path()
      ..moveTo(0, size.height * 0.72)
      ..lineTo(size.width * 0.25, size.height * 0.68)
      ..lineTo(size.width * 0.45, size.height * 0.71)
      ..lineTo(size.width * 0.7, size.height * 0.65)
      ..lineTo(size.width, size.height * 0.7)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, silhouettePaint);

    final centerGlow = Offset(size.width * 0.52, size.height * 0.56);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.cinemaGlowCenter.withValues(alpha: 0.45),
          AppColors.cinemaGlowMid.withValues(alpha: 0.25),
          AppColors.cinemaGlowOuter.withValues(alpha: 0.1),
          AppColors.transparent,
        ],
        stops: const [0.0, 0.25, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: centerGlow, radius: size.width * 0.65));
    canvas.drawCircle(centerGlow, size.width * 0.65, glowPaint);

    final beamPaint = Paint()
      ..color = AppColors.cinemaSteelBlue.withValues(alpha: 0.12)
      ..strokeWidth = 2.0;
    canvas.drawLine(
      Offset(0, size.height * 0.2),
      Offset(size.width, size.height * 0.45),
      beamPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.1, 0),
      Offset(size.width * 0.9, size.height),
      beamPaint..strokeWidth = 1.0,
    );

    final random = math.Random(76909193);
    for (var i = 0; i < 28; i++) {
      final x = size.width * (0.25 + random.nextDouble() * 0.5);
      final y = size.height * (0.35 + random.nextDouble() * 0.4);
      final radius = 1.2 + random.nextDouble() * 2.8;
      final opacity = 0.35 + random.nextDouble() * 0.55;
      final sparkPaint = Paint()
        ..color = (random.nextBool()
                ? AppColors.cinemaSparkGold
                : AppColors.cinemaSparkOrange)
            .withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
