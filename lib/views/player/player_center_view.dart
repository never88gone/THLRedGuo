import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 播放器居中操作按键区（包含大播放/暂停圆钮、上一集、下一集）
/// 深度针对移动端（紧凑防遮挡、轻巧通透）与桌面端（悬停动效、光标手型、舒展大气）进行专门适配
class PlayerCenterView extends StatelessWidget {
  const PlayerCenterView({
    super.key,
    required this.playing,
    required this.showSkip,
    required this.onTogglePlayback,
    this.onPrevious,
    this.onNext,
    this.isDesktop,
  });

  final bool playing;
  final bool showSkip;
  final VoidCallback onTogglePlayback;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// 可选显式指定桌面端模式，缺省时自动读取 [AppLayout.isDesktop] 与视口宽度
  final bool? isDesktop;

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop ?? AppLayout.isDesktop(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    // 当为移动端或桌面端窗口收缩至小屏（如分屏/浮窗小于 580dp）时，自动采用紧凑美化尺寸
    final compact = !desktop || screenWidth < 580;

    final mainSize = compact ? 54.0 : 64.0;
    final mainIconSize = compact ? 28.0 : 32.0;
    final skipSize = compact ? 38.0 : 44.0;
    final skipIconSize = compact ? 20.0 : 22.0;
    final spacing = compact ? 20.0 : 28.0;

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSkip) ...[
            _CenterActionButton(
              buttonKey: const ValueKey('player-previous'),
              tooltip: onPrevious != null ? '上一集' : '已是第一集',
              icon: Icons.skip_previous_rounded,
              size: skipSize,
              iconSize: skipIconSize,
              isPrimary: false,
              isDesktop: desktop,
              onPressed: onPrevious,
            ),
            SizedBox(width: spacing),
          ],
          _CenterActionButton(
            buttonKey: const ValueKey('player-toggle'),
            tooltip: desktop
                ? (playing ? '暂停播放 (Space)' : '开始播放 (Space)')
                : (playing ? '暂停播放' : '开始播放'),
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: mainSize,
            iconSize: mainIconSize,
            isPrimary: true,
            isDesktop: desktop,
            // 播放图标为三角形，视觉重心略偏左，微调向右偏移实现真正绝对居中平衡
            iconOffset: playing
                ? Offset.zero
                : Offset(desktop ? 2.0 : 1.5, 0),
            onPressed: onTogglePlayback,
          ),
          if (showSkip) ...[
            SizedBox(width: spacing),
            _CenterActionButton(
              buttonKey: const ValueKey('player-next'),
              tooltip: onNext != null ? '下一集' : '已是最后一集',
              icon: Icons.skip_next_rounded,
              size: skipSize,
              iconSize: skipIconSize,
              isPrimary: false,
              isDesktop: desktop,
              onPressed: onNext,
            ),
          ],
        ],
      ),
    );
  }
}

/// 播放器居中操作交互圆钮
class _CenterActionButton extends StatefulWidget {
  const _CenterActionButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.isPrimary,
    required this.isDesktop,
    required this.onPressed,
    this.iconOffset = Offset.zero,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final double size;
  final double iconSize;
  final bool isPrimary;
  final bool isDesktop;
  final VoidCallback? onPressed;
  final Offset iconOffset;

  @override
  State<_CenterActionButton> createState() => _CenterActionButtonState();
}

class _CenterActionButtonState extends State<_CenterActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    double scale = 1.0;
    if (!enabled) {
      scale = 1.0;
    } else if (_isPressed) {
      scale = 0.92;
    } else if (_isHovered && widget.isDesktop) {
      scale = widget.isPrimary ? 1.08 : 1.06;
    }

    // 阴影与光晕设置
    List<BoxShadow> shadows;
    if (!enabled) {
      shadows = const [];
    } else if (widget.isPrimary) {
      shadows = [
        BoxShadow(
          color: _isHovered
              ? AppColors.blackWithAlpha(0.50)
              : AppColors.blackWithAlpha(0.35),
          blurRadius: _isHovered ? 20 : 16,
          offset: Offset(0, _isHovered ? 6 : 4),
        ),
        if (_isHovered && widget.isDesktop)
          BoxShadow(
            color: AppColors.hongguoRedWithAlpha(0.20),
            blurRadius: 14,
            spreadRadius: 1,
          ),
      ];
    } else {
      shadows = [
        BoxShadow(
          color: AppColors.blackWithAlpha(0.25),
          blurRadius: _isHovered ? 14 : 10,
          offset: Offset(0, _isHovered ? 3 : 2),
        ),
      ];
    }

    // 背景色与边框色彩
    final Color bgColor;
    final Color borderColor;
    final double borderWidth;

    if (widget.isPrimary) {
      bgColor = _isHovered && widget.isDesktop
          ? AppColors.playerCenterMainBgHover
          : AppColors.playerCenterMainBg;
      borderColor = _isHovered && widget.isDesktop
          ? AppColors.playerCenterMainBorderHover
          : AppColors.playerCenterMainBorder;
      borderWidth = _isHovered && widget.isDesktop ? 1.2 : 1.0;
    } else {
      bgColor = _isHovered && widget.isDesktop
          ? AppColors.playerCenterSkipBgHover
          : AppColors.playerCenterSkipBg;
      borderColor = _isHovered && widget.isDesktop
          ? AppColors.playerCenterSkipBorderHover
          : AppColors.playerCenterSkipBorder;
      borderWidth = _isHovered && widget.isDesktop ? 1.0 : 0.8;
    }

    final buttonContent = AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 140),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: shadows,
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: borderColor,
                    width: borderWidth,
                  ),
                ),
                alignment: Alignment.center,
                child: Transform.translate(
                  offset: widget.iconOffset,
                  child: Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _isHovered = true) : null,
        onExit: enabled ? (_) => setState(() => _isHovered = false) : null,
        child: GestureDetector(
          key: widget.buttonKey,
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _isPressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _isPressed = false) : null,
          onTap: widget.onPressed,
          child: buttonContent,
        ),
      ),
    );
  }
}
