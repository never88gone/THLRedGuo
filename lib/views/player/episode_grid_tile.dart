import 'package:flutter/material.dart';

import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 播放器选集面板中的单集按钮卡片
class EpisodeGridTile extends StatelessWidget {
  const EpisodeGridTile({
    super.key,
    required this.episode,
    required this.epIndex,
    required this.isPlaying,
    required this.onTap,
  });

  final Episode episode;
  final int epIndex;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('episode-option-$epIndex'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isPlaying ? null : AppColors.darkSurfaceHigh,
          gradient: isPlaying
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.hongguoRed,
                    AppColors.hongguoOrange,
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: isPlaying
              ? null
              : Border.all(
                  color: AppColors.whiteWithAlpha(0.03),
                  width: 0.8,
                ),
          boxShadow: isPlaying
              ? [
                  BoxShadow(
                    color: AppColors.hongguoRedWithAlpha(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${episode.number}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isPlaying ? FontWeight.w800 : FontWeight.w600,
                    color: isPlaying ? AppColors.white : AppColors.textPrimaryDark,
                  ),
                ),
                if (isPlaying) ...[
                  const SizedBox(height: 2),
                  const Text(
                    '播放中',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
