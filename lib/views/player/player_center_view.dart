import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 播放器居中操作按键区（包含大播放/暂停圆钮、上一集、下一集）
class PlayerCenterView extends StatelessWidget {
  const PlayerCenterView({
    super.key,
    required this.playing,
    required this.showSkip,
    required this.onTogglePlayback,
    this.onPrevious,
    this.onNext,
  });

  final bool playing;
  final bool showSkip;
  final VoidCallback onTogglePlayback;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSkip) ...[
            Container(
              decoration: BoxDecoration(
                color: const Color(0x40000000),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x26FFFFFF), width: 0.8),
              ),
              child: IconButton(
                tooltip: '上一集',
                iconSize: 26,
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous_rounded, color: AppColors.white),
              ),
            ),
            const SizedBox(width: 20),
          ],
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x80252836),
                  Color(0x9912141C),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0x40FFFFFF),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: IconButton.filledTonal(
              tooltip: playing ? '暂停播放' : '开始播放',
              iconSize: 44,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.transparent,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.all(16),
              ),
              onPressed: onTogglePlayback,
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ),
          if (showSkip) ...[
            const SizedBox(width: 20),
            Container(
              decoration: BoxDecoration(
                color: const Color(0x40000000),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x26FFFFFF), width: 0.8),
              ),
              child: IconButton(
                tooltip: '下一集',
                iconSize: 26,
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded, color: AppColors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
