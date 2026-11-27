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
    this.onCast,
    this.casting = false,
  });

  final String title;
  final bool fullscreen;
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onFullscreen;
  final VoidCallback? onCast;
  final bool casting;

  Widget _iconButton({
    Key? key,
    required String tooltip,
    required VoidCallback onPressed,
    required IconData icon,
    bool highlighted = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? AppColors.hongguoRed : AppColors.black35,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: highlighted ? AppColors.hongguoRed : AppColors.white15,
          width: 0.8,
        ),
      ),
      child: IconButton(
        key: key,
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
        padding: EdgeInsets.only(top: extraTop, left: 8, right: 8),
        child: Row(
          children: [
            _iconButton(
              tooltip: fullscreen ? '退出全屏' : '返回',
              onPressed: fullscreen ? onFullscreen : onBack,
              icon: fullscreen
                  ? Icons.arrow_back_rounded
                  : Icons.arrow_back_ios_new_rounded,
            ),
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
            if (onCast != null)
              _iconButton(
                key: const ValueKey('player-cast-button'),
                tooltip: casting ? '正在投屏' : '投屏',
                onPressed: onCast!,
                highlighted: casting,
                icon: casting
                    ? Icons.cast_connected_rounded
                    : Icons.cast_rounded,
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
