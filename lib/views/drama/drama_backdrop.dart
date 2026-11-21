import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/drama/cached_cover_image.dart';
import 'package:THLRedLook/views/drama/drama_cover_view.dart';

/// 短剧海报毛玻璃托底背景组件，突出剧目图片质感并提供沉浸式环境光晕
class DramaBackdrop extends StatelessWidget {
  const DramaBackdrop({
    super.key,
    required this.drama,
    required this.repository,
    this.sigma = 28.0,
    this.dimColor,
    this.gradient,
    this.fadeBottom = false,
    this.child,
  });

  final Drama drama;
  final AppRepository repository;
  final double sigma;
  final Color? dimColor;
  final Gradient? gradient;
  final bool fadeBottom;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fallbackColor = isDark
        ? AppColors.darkBackground
        : AppColors.lightSurfaceHigh;

    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        if (!DramaCover.imagesDisabled && drama.cover.isNotEmpty)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.mirror,
              ),
              child: Transform.scale(
                scale: 1.18,
                child: CachedCoverImage(
                  key: ValueKey(
                    'backdrop-${drama.cleanSourceId.isNotEmpty ? drama.cleanSourceId : drama.id}',
                  ),
                  drama: drama,
                  repository: repository,
                  placeholder: Container(color: fallbackColor),
                ),
              ),
            ),
          )
        else
          Container(color: fallbackColor),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  dimColor ??
                  (isDark
                      ? AppColors.black.withValues(alpha: 0.45)
                      : AppColors.white.withValues(alpha: 0.60)),
              gradient: gradient,
            ),
          ),
        ),
        if (child != null) Positioned.fill(child: child!),
      ],
    );

    if (fadeBottom) {
      content = ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.black,
              AppColors.black,
              AppColors.black80,
              AppColors.black30,
              AppColors.transparent,
            ],
            stops: [0.0, 0.40, 0.68, 0.88, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: content,
      );
    }

    return content;
  }
}
