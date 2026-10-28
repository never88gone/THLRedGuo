import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 播放器顶部应用与返回栏（符合手机端与桌面端交互规范）
class PlayerTopBarView extends StatelessWidget {
  const PlayerTopBarView({
    super.key,
    required this.title,
    required this.fullscreen,
    required this.compact,
    required this.onBack,
    required this.onFullscreen,
  });

  final String title;
  final bool fullscreen;
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onFullscreen;

  Widget _iconButton({
    required String tooltip,
    required VoidCallback onPressed,
    required IconData icon,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x59000000),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x26FFFFFF), width: 0.8),
      ),
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.white),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final topPadding = fullscreen ? MediaQuery.paddingOf(context).top : 0.0;
    final double extraTop = topPadding > 0
        ? (topPadding + (compact ? 4.0 : 8.0))
        : (compact ? 8.0 : 8.0);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: extraTop),
        child: Row(
          children: [
            _iconButton(
              tooltip: fullscreen ? '退出全屏' : '返回',
              onPressed: fullscreen ? onFullscreen : onBack,
              icon: fullscreen
                  ? Icons.arrow_back_rounded
                  : Icons.arrow_back_ios_new_rounded,
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 6,
                        color: AppColors.black,
                      ),
                    ],
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (compact)
              _iconButton(
                tooltip: '旋转与全屏',
                onPressed: onFullscreen,
                icon: Icons.screen_rotation_alt_rounded,
              ),
          ],
        ),
      ),
    );
  }
}
