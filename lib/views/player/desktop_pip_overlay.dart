import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 桌面迷你置顶画中画模式下的悬浮交互播控层
class DesktopPipOverlay extends StatefulWidget {
  const DesktopPipOverlay({
    super.key,
    required this.player,
    required this.title,
    required this.onRestore,
    required this.onBack,
    required this.onTogglePlayback,
  });

  final Player player;
  final String title;
  final Future<void> Function()? onRestore;
  final VoidCallback onBack;
  final VoidCallback onTogglePlayback;

  @override
  State<DesktopPipOverlay> createState() => _DesktopPipOverlayState();
}

class _DesktopPipOverlayState extends State<DesktopPipOverlay> {
  bool _hovered = false;
  Timer? _hideTimer;

  void _onHover(bool hover) {
    _hideTimer?.cancel();
    if (hover) {
      setState(() => _hovered = true);
    } else {
      _hideTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _hovered = false);
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHover(true),
      onExit: (_) => _onHover(false),
      onHover: (_) => _onHover(true),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          _onHover(true);
          widget.onTogglePlayback();
        },
        child: AnimatedOpacity(
          opacity: _hovered ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.blackWithAlpha(0.7),
                  Colors.transparent,
                  Colors.transparent,
                  AppColors.blackWithAlpha(0.7),
                ],
                stops: const [0.0, 0.25, 0.75, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // 顶部操作栏
                Positioned(
                  top: 8,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (widget.onRestore != null)
                        _iconButton(
                          icon: Icons.open_in_full_rounded,
                          tooltip: '还原大窗 (P)',
                          onTap: widget.onRestore!,
                        ),
                      const SizedBox(width: 4),
                      _iconButton(
                        icon: Icons.close_rounded,
                        tooltip: '关闭',
                        onTap: widget.onBack,
                      ),
                    ],
                  ),
                ),
                // 居中播放/暂停指示
                Center(
                  child: StreamBuilder<bool>(
                    stream: widget.player.stream.playing,
                    initialData: widget.player.state.playing,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data ?? true;
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.blackWithAlpha(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: AppColors.white,
                          size: 28,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.blackWithAlpha(0.55),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, color: AppColors.white, size: 16),
          ),
        ),
      ),
    );
  }
}
