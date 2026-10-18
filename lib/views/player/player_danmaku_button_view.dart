import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 播放器右上方轻量级弹幕控制开关
class PlayerDanmakuButtonView extends StatelessWidget {
  const PlayerDanmakuButtonView({
    super.key,
    required this.enabled,
    required this.danmakuEnabled,
    required this.danmakuStatus,
    required this.swipeEnabled,
    required this.onTap,
    this.onSettings,
    this.canRetry = false,
  });

  final bool enabled;
  final bool danmakuEnabled;
  final String danmakuStatus;
  final bool swipeEnabled;
  final VoidCallback? onTap;
  final VoidCallback? onSettings;
  final bool canRetry;

  @override
  Widget build(BuildContext context) {
    final tooltip = danmakuStatus.isEmpty
        ? (danmakuEnabled ? '轻触关闭弹幕 · 长按设置样式' : '轻触打开弹幕 · 长按设置样式')
        : danmakuStatus;

    return Align(
      alignment: swipeEnabled
          ? const Alignment(1.0, -0.42)
          : Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: swipeEnabled ? 8 : 4),
        child: Tooltip(
          message: tooltip,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: tooltip,
            child: GestureDetector(
              key: const ValueKey('player-danmaku-toggle'),
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? onTap : null,
              onLongPress: enabled ? onSettings : null,
              child: SizedBox(
                width: 44,
                height: 48,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: danmakuEnabled
                          ? AppColors.hongguoRedWithAlpha(0.22)
                          : AppColors.playerOverlayButton,
                      border: Border.all(
                        color: danmakuEnabled
                            ? AppColors.hongguoRed
                            : AppColors.whiteWithAlpha(0.24),
                        width: 1.2,
                      ),
                    ),
                    child: canRetry
                        ? const Icon(Icons.refresh_rounded, size: 21, color: AppColors.white)
                        : Text(
                            '弹',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: danmakuEnabled
                                  ? AppColors.hongguoRed
                                  : AppColors.whiteWithAlpha(0.88),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
