import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 播放器底部控制层（进度条、清晰度、倍速、音量、画中画、全屏）
class PlayerBottomBarView extends StatelessWidget {
  const PlayerBottomBarView({
    super.key,
    required this.constraints,
    required this.fullscreen,
    required this.swipeEnabled,
    required this.enabled,
    required this.speed,
    required this.qualityLabel,
    required this.duration,
    required this.position,
    required this.buffered,
    required this.seekValue,
    required this.onSpeed,
    required this.onQuality,
    required this.onFullscreen,
    required this.onSeekStart,
    required this.onSeekChange,
    required this.onSeekEnd,
    this.volume = 100.0,
    this.onVolumeChange,
    this.onToggleMute,
    this.showVolumeControl,
    this.onEpisodes,
    this.onComments,
    this.onPush,
    this.onPictureInPicture,
    this.pictureInPictureRequested = false,
  });

  final BoxConstraints constraints;
  final bool fullscreen;
  final bool swipeEnabled;
  final bool enabled;
  final bool pictureInPictureRequested;
  final double speed;
  final String qualityLabel;
  final double duration;
  final double position;
  final double buffered;
  final double? seekValue;
  final double volume;
  final ValueChanged<double>? onVolumeChange;
  final VoidCallback? onToggleMute;
  final bool? showVolumeControl;
  final VoidCallback onSpeed;
  final VoidCallback onQuality;
  final VoidCallback onFullscreen;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChange;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback? onEpisodes;
  final VoidCallback? onComments;
  final VoidCallback? onPush;
  final VoidCallback? onPictureInPicture;

  Widget _toolButton({
    required BuildContext context,
    Key? key,
    required String tooltip,
    required Widget child,
    required VoidCallback? onPressed,
    double visualWidth = 36,
    bool selected = false,
  }) {
    final isEnabled = onPressed != null;
    final foreground = selected
        ? AppColors.white
        : AppColors.whiteWithAlpha(isEnabled ? 0.92 : 0.36);
    final background = selected
        ? AppColors.hongguoRed
        : const Color(0x40000000);
    final border = selected
        ? AppColors.hongguoRed
        : const Color(0x26FFFFFF);
    final targetWidth = visualWidth < 40 ? 48.0 : visualWidth + 8;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: isEnabled,
        label: tooltip,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: targetWidth,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: visualWidth,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border, width: 0.8),
                  boxShadow: selected ? AppShadows.pillGlow : null,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground, size: 20),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13.5,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopVolumeControl(BuildContext context) {
    final isMuted = volume <= 0;
    final IconData volumeIcon;
    if (isMuted) {
      volumeIcon = Icons.volume_off_rounded;
    } else if (volume < 30) {
      volumeIcon = Icons.volume_mute_rounded;
    } else if (volume < 70) {
      volumeIcon = Icons.volume_down_rounded;
    } else {
      volumeIcon = Icons.volume_up_rounded;
    }

    final isEnabled = enabled && (onVolumeChange != null || onToggleMute != null);

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && isEnabled && onVolumeChange != null) {
          final delta = event.scrollDelta.dy < 0 ? 5.0 : -5.0;
          onVolumeChange!((volume + delta).clamp(0.0, 100.0));
        }
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0x40000000),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x26FFFFFF), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: isMuted ? '取消静音 (M)' : '静音 (M)',
              child: Semantics(
                button: true,
                enabled: isEnabled,
                label: isMuted ? '取消静音' : '静音',
                child: GestureDetector(
                  key: const ValueKey('player-volume-button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? onToggleMute : null,
                  child: SizedBox(
                    width: 32,
                    height: 36,
                    child: Center(
                      child: Icon(
                        volumeIcon,
                        size: 20,
                        color: AppColors.whiteWithAlpha(isEnabled ? 0.92 : 0.36),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 76,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: AppColors.hongguoRed,
                  inactiveTrackColor: AppColors.playerProgressInactive,
                  thumbColor: AppColors.white,
                  overlayColor: AppColors.hongguoRedWithAlpha(0.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  key: const ValueKey('player-volume-slider'),
                  value: volume.clamp(0.0, 100.0),
                  min: 0.0,
                  max: 100.0,
                  semanticFormatterCallback: (val) => '音量 ${val.round()}%',
                  onChanged: enabled ? onVolumeChange : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clusteredToolRow(List<Widget> tools, {bool desktop = false}) {
    if (tools.isEmpty) return const SizedBox.shrink();
    if (desktop || tools.length <= 5) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (int i = 0; i < tools.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            tools[i],
          ],
        ],
      );
    }
    final leftCount = tools.length ~/ 2;
    return Row(
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: tools.take(leftCount).toList()),
        const Spacer(),
        Row(mainAxisSize: MainAxisSize.min, children: tools.skip(leftCount).toList()),
      ],
    );
  }

  Widget _progressRow(BuildContext context) {
    final effectivePosition = seekValue ?? position;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                formatPosition(effectivePosition),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                textAlign: TextAlign.end,
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: AppColors.hongguoRed,
                  inactiveTrackColor: AppColors.playerProgressInactive,
                  secondaryActiveTrackColor: AppColors.playerProgressBuffered,
                  thumbColor: AppColors.hongguoRed,
                  overlayColor: AppColors.hongguoRedWithAlpha(0.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  key: const ValueKey('player-progress'),
                  value: effectivePosition.clamp(0, duration > 0 ? duration : 1),
                  max: duration > 0 ? duration : 1,
                  secondaryTrackValue: buffered.clamp(0, duration > 0 ? duration : 1),
                  semanticFormatterCallback: formatPosition,
                  onChangeStart: enabled && duration > 0 ? onSeekStart : null,
                  onChangeEnd: enabled && duration > 0 ? onSeekEnd : null,
                  onChanged: enabled && duration > 0 ? onSeekChange : null,
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                formatPosition(duration),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.whiteWithAlpha(0.75),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = constraints.maxWidth;
    final isDesktop = showVolumeControl ?? AppLayout.isDesktop(context);
    final showSpeedQuality = swipeEnabled || width >= 540;

    final tools = [
      if (showSpeedQuality) ...[
        _toolButton(
          context: context,
          key: const ValueKey('player-speed'),
          tooltip: '倍速',
          onPressed: enabled ? onSpeed : null,
          visualWidth: 50,
          child: Text('${speed}x'),
        ),
        _toolButton(
          context: context,
          key: const ValueKey('player-quality'),
          tooltip: '清晰度',
          onPressed: enabled ? onQuality : null,
          visualWidth: 52,
          child: Text(qualityLabel),
        ),
      ],
      if (onComments != null)
        _toolButton(
          context: context,
          key: const ValueKey('player-comments'),
          tooltip: '评论',
          onPressed: enabled ? onComments : null,
          child: const Icon(Icons.chat_bubble_outline_rounded),
        ),
      if (isDesktop) _desktopVolumeControl(context),
      if (onPictureInPicture != null)
        _toolButton(
          context: context,
          key: const ValueKey('player-picture-in-picture'),
          tooltip: pictureInPictureRequested ? '正在启动画中画' : '画中画',
          onPressed: (enabled && !pictureInPictureRequested)
              ? onPictureInPicture
              : null,
          child: pictureInPictureRequested
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_in_picture_alt_rounded),
        ),
      if (fullscreen && onEpisodes != null)
        _toolButton(
          context: context,
          key: const ValueKey('player-episodes'),
          tooltip: '选集',
          onPressed: enabled ? onEpisodes : null,
          child: const Text('选集'),
        ),

      if (!swipeEnabled)
        _toolButton(
          context: context,
          key: const ValueKey('player-fullscreen'),
          tooltip: fullscreen ? '退出全屏' : '全屏播放',
          onPressed: onFullscreen,
          child: Icon(
            fullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
          ),
        ),
    ];

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        minimum: EdgeInsets.only(bottom: fullscreen ? 14.0 : 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: _clusteredToolRow(tools, desktop: isDesktop),
            ),
            _progressRow(context),
          ],
        ),
      ),
    );
  }
}
