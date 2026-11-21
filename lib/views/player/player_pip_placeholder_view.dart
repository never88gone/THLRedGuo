import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 画中画激活状态下的播放器主视口占位提示视图
class PlayerPipPlaceholderView extends StatelessWidget {
  const PlayerPipPlaceholderView({
    super.key,
    required this.title,
    required this.onBack,
    this.onRestorePictureInPicture,
  });

  final String title;
  final VoidCallback onBack;
  final Future<void> Function()? onRestorePictureInPicture;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: AppColors.blackWithAlpha(0.6),
                shape: const CircleBorder(),
                child: IconButton(
                  key: const ValueKey('player-pip-viewport-back'),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.white,
                    size: 20,
                  ),
                  tooltip: '退出播放',
                  onPressed: onBack,
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 28,
            ),
            decoration: BoxDecoration(
              color: AppColors.blackWithAlpha(0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.hongguoRed.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.picture_in_picture_alt_rounded,
                    color: AppColors.hongguoRed,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '正在画中画窗口中播放',
                  style: TextStyle(
                    color: AppColors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('player-pip-restore-btn'),
                      onPressed: onRestorePictureInPicture,
                      icon: const Icon(Icons.fullscreen_rounded, size: 18),
                      label: const Text('恢复应用内播放'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.hongguoRed,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('player-pip-exit-btn'),
                      onPressed: onBack,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('退出播放'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.white,
                        side: BorderSide(
                          color: AppColors.white.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
