import 'dart:async';

import 'package:flutter/material.dart';

import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/core/cast/haw_cast_service.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 正在投屏时的播放器遥控覆盖视图
class HawCastOverlay extends StatefulWidget {
  const HawCastOverlay({
    super.key,
    required this.title,
    required this.fullscreen,
    required this.onBack,
    required this.onFullscreen,
    required this.onSwitchDevice,
    required this.onStopCast,
    required this.onEpisodes,
    this.onPrevious,
    this.onNext,
  });

  final String title;
  final bool fullscreen;
  final VoidCallback onBack;
  final VoidCallback onFullscreen;
  final VoidCallback onSwitchDevice;
  final Future<void> Function() onStopCast;
  final VoidCallback onEpisodes;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<HawCastOverlay> createState() => _HawCastOverlayState();
}

class _HawCastOverlayState extends State<HawCastOverlay> {
  final HawCastService _service = HawCastService.instance;
  double? _seekValue;
  double _rate = 1.0;

  String _stateLabel(HawCastPlayState state) => switch (state) {
    HawCastPlayState.buffering => '接收端缓冲中...',
    HawCastPlayState.playing => '正在接收端播放',
    HawCastPlayState.paused => '已暂停投屏播放',
    HawCastPlayState.stopped => '投屏已停止',
    HawCastPlayState.error => '接收端播放异常',
    HawCastPlayState.idle => '已连接接收端',
  };

  void _cycleRate() {
    const rates = [1.0, 1.25, 1.5, 2.0];
    final currentIdx = rates.indexOf(_rate);
    final nextRate = rates[(currentIdx + 1) % rates.length];
    setState(() => _rate = nextRate);
    unawaited(_service.sendControl(HawCastControlCommand.rate, rate: nextRate));
  }

  Widget _roundAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: primary
            ? AppColors.hongguoRed
            : AppColors.whiteWithAlpha(enabled ? 0.14 : 0.06),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: primary ? 54 : 42,
            height: primary ? 54 : 42,
            child: Icon(
              icon,
              size: primary ? 30 : 22,
              color: enabled ? AppColors.white : AppColors.white38,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = widget.fullscreen ? MediaQuery.paddingOf(context).top : 0.0;

    return ColoredBox(
      color: AppColors.darkBackground,
      child: SafeArea(
        top: false,
        bottom: true,
        child: ListenableBuilder(
          listenable: _service,
          builder: (context, _) {
            final device = _service.activeDevice;
            final status = _service.status;
            final isPlaying = status.state == HawCastPlayState.playing ||
                status.state == HawCastPlayState.buffering;
            final duration = status.duration > 0 ? status.duration : 1.0;
            final position = (_seekValue ?? status.position).clamp(0.0, duration);

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: topPadding > 0 ? topPadding + 4 : 8,
                    left: 8,
                    right: 12,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: widget.fullscreen ? '退出全屏' : '返回',
                        onPressed: widget.fullscreen ? widget.onFullscreen : widget.onBack,
                        icon: Icon(
                          widget.fullscreen
                              ? Icons.arrow_back_rounded
                              : Icons.arrow_back_ios_new_rounded,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: widget.fullscreen ? '退出全屏' : '全屏遥控',
                        onPressed: widget.onFullscreen,
                        icon: Icon(
                          widget.fullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: AppColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.black35,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.hongguoRedWithAlpha(0.45),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.cast_connected_rounded,
                                    size: 16,
                                    color: AppColors.hongguoRed,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '正在投屏 · ${device?.name ?? '接收端'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _stateLabel(status.state),
                              style: const TextStyle(
                                color: AppColors.white70,
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _roundAction(
                                  tooltip: '上一集',
                                  icon: Icons.skip_previous_rounded,
                                  onPressed: widget.onPrevious,
                                ),
                                const SizedBox(width: 24),
                                _roundAction(
                                  tooltip: isPlaying ? '暂停' : '播放',
                                  icon: isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  primary: true,
                                  onPressed: () {
                                    unawaited(
                                      _service.sendControl(
                                        isPlaying
                                            ? HawCastControlCommand.pause
                                            : HawCastControlCommand.play,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 24),
                                _roundAction(
                                  tooltip: '下一集',
                                  icon: Icons.skip_next_rounded,
                                  onPressed: widget.onNext,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Text(
                                  formatPosition(position),
                                  style: const TextStyle(
                                    color: AppColors.white70,
                                    fontSize: 11.5,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      activeTrackColor: AppColors.hongguoRed,
                                      inactiveTrackColor:
                                          AppColors.playerProgressInactive,
                                      thumbColor: AppColors.white,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                    ),
                                    child: Slider(
                                      value: position,
                                      min: 0.0,
                                      max: duration,
                                      onChanged: (val) =>
                                          setState(() => _seekValue = val),
                                      onChangeEnd: (val) {
                                        setState(() => _seekValue = null);
                                        unawaited(
                                          _service.sendControl(
                                            HawCastControlCommand.seek,
                                            position: val,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                Text(
                                  formatPosition(status.duration),
                                  style: const TextStyle(
                                    color: AppColors.white70,
                                    fontSize: 11.5,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _cycleRate,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.white,
                                    side: const BorderSide(color: AppColors.white24),
                                  ),
                                  icon: const Icon(Icons.speed_rounded, size: 16),
                                  label: Text('${_rate}x'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: widget.onEpisodes,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.white,
                                    side: const BorderSide(color: AppColors.white24),
                                  ),
                                  icon: const Icon(
                                    Icons.playlist_play_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('选集'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: widget.onSwitchDevice,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.white,
                                    side: const BorderSide(color: AppColors.white24),
                                  ),
                                  icon: const Icon(Icons.devices_rounded, size: 16),
                                  label: const Text('换设备'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => unawaited(widget.onStopCast()),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.hongguoRedLight,
                                    side: BorderSide(
                                      color: AppColors.hongguoRedWithAlpha(0.55),
                                    ),
                                  ),
                                  icon: const Icon(Icons.close_rounded, size: 16),
                                  label: const Text('退出投屏'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
