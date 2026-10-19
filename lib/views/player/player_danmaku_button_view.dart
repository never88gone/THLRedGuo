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
        ? (danmakuEnabled ? '轻触关闭弹幕 · 设置样式' : '轻触打开弹幕 · 设置样式')
        : danmakuStatus;

    return Align(
      alignment: swipeEnabled
          ? const Alignment(1.0, -0.42)
          : Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: swipeEnabled ? 8 : 4),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.playerOverlayButton,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: danmakuEnabled
                  ? AppColors.hongguoRed.withValues(alpha: 0.6)
                  : AppColors.whiteWithAlpha(0.24),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
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
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: danmakuEnabled
                            ? AppColors.hongguoRed
                            : AppColors.transparent,
                      ),
                      child: canRetry
                          ? const Icon(Icons.refresh_rounded, size: 18, color: AppColors.white)
                          : Text(
                              '弹',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                color: danmakuEnabled
                                    ? AppColors.white
                                    : AppColors.whiteWithAlpha(0.88),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              if (onSettings != null) ...[
                const SizedBox(width: 2),
                Tooltip(
                  message: '弹幕样式设置',
                  child: Semantics(
                    button: true,
                    enabled: enabled,
                    label: '弹幕样式设置',
                    child: GestureDetector(
                      key: const ValueKey('player-danmaku-settings-button'),
                      behavior: HitTestBehavior.opaque,
                      onTap: enabled ? onSettings : null,
                      child: Container(
                        width: 28,
                        height: 32,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.tune_rounded,
                          size: 17,
                          color: AppColors.whiteWithAlpha(danmakuEnabled ? 0.95 : 0.60),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
