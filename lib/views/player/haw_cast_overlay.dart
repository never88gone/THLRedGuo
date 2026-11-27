import 'dart:async';

import 'package:flutter/material.dart';

import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/core/cast/haw_cast_service.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 正在投屏时的播放器遥控控制器页面（同时适配手机半屏紧凑视图与全屏/桌面大屏视图）
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

  void _stepVolume(double currentVolume, double delta) {
    final nextVol = (currentVolume + delta).clamp(0.0, 1.0);
    unawaited(
      _service.sendControl(HawCastControlCommand.volume, volume: nextVol),
    );
  }

  Widget _roundAction({
    Key? key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
    bool compact = false,
  }) {
    final enabled = onPressed != null;
    final size = primary ? (compact ? 42.0 : 54.0) : (compact ? 34.0 : 42.0);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: primary
            ? AppColors.hongguoRed
            : AppColors.whiteWithAlpha(enabled ? 0.14 : 0.06),
        shape: const CircleBorder(),
        child: InkWell(
          key: key,
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: primary ? (compact ? 24 : 30) : (compact ? 18 : 22),
              color: enabled ? AppColors.white : AppColors.white38,
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipAction({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
    bool compact = false,
  }) {
    return OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor:
            danger ? AppColors.hongguoRedLight : AppColors.white,
        backgroundColor: danger ? AppColors.accentSubtle12 : AppColors.black35,
        side: BorderSide(
          color: danger
              ? AppColors.hongguoRedWithAlpha(0.55)
              : AppColors.white24,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 8,
        ),
        minimumSize: Size(0, compact ? 28 : 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: compact ? 14 : 16),
      label: Text(
        label,
        style: TextStyle(fontSize: compact ? 11.5 : 12.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = widget.fullscreen ? MediaQuery.paddingOf(context).top : 0.0;

    return ColoredBox(
      key: const ValueKey('haw-cast-controller-page'),
      color: AppColors.darkBackground,
      child: SafeArea(
        top: false,
        bottom: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 300;
            return ListenableBuilder(
              listenable: _service,
              builder: (context, _) {
                final device = _service.activeDevice;
                final status = _service.status;
                final isPlaying = status.state == HawCastPlayState.playing ||
                    status.state == HawCastPlayState.buffering;
                final duration = status.duration > 0 ? status.duration : 1.0;
                final position =
                    (_seekValue ?? status.position).clamp(0.0, duration);

                return Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top: topPadding > 0 ? topPadding + 2 : (compact ? 2 : 6),
                        left: 6,
                        right: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: widget.fullscreen ? '退出全屏' : '返回',
                            constraints: BoxConstraints.tightFor(
                              width: compact ? 36 : 42,
                              height: compact ? 36 : 42,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: widget.fullscreen
                                ? widget.onFullscreen
                                : widget.onBack,
                            icon: Icon(
                              widget.fullscreen
                                  ? Icons.arrow_back_rounded
                                  : Icons.arrow_back_ios_new_rounded,
                              size: compact ? 18 : 22,
                              color: AppColors.white,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: compact ? 13 : 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: widget.fullscreen ? '退出全屏' : '全屏遥控',
                            constraints: BoxConstraints.tightFor(
                              width: compact ? 36 : 42,
                              height: compact ? 36 : 42,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: widget.onFullscreen,
                            icon: Icon(
                              widget.fullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              size: compact ? 20 : 22,
                              color: AppColors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 14 : 22,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 10 : 14,
                                    vertical: compact ? 4 : 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.black35,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color:
                                          AppColors.hongguoRedWithAlpha(0.45),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.cast_connected_rounded,
                                        size: compact ? 14 : 16,
                                        color: AppColors.hongguoRed,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          '${device?.name ?? '接收端'} · ${_stateLabel(status.state)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: AppColors.white,
                                            fontSize: compact ? 11.5 : 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: compact ? 8 : 18),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _roundAction(
                                      key: const ValueKey('cast-ctrl-vol-down'),
                                      tooltip: '音量减',
                                      icon: Icons.volume_down_rounded,
                                      compact: compact,
                                      onPressed: () =>
                                          _stepVolume(status.volume, -0.15),
                                    ),
                                    SizedBox(width: compact ? 12 : 18),
                                    _roundAction(
                                      key: const ValueKey('cast-ctrl-prev'),
                                      tooltip: '上一集',
                                      icon: Icons.skip_previous_rounded,
                                      compact: compact,
                                      onPressed: widget.onPrevious,
                                    ),
                                    SizedBox(width: compact ? 14 : 22),
                                    _roundAction(
                                      key: const ValueKey(
                                        'cast-ctrl-play-pause',
                                      ),
                                      tooltip: isPlaying ? '暂停' : '播放',
                                      icon: isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      primary: true,
                                      compact: compact,
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
                                    SizedBox(width: compact ? 14 : 22),
                                    _roundAction(
                                      key: const ValueKey('cast-ctrl-next'),
                                      tooltip: '下一集',
                                      icon: Icons.skip_next_rounded,
                                      compact: compact,
                                      onPressed: widget.onNext,
                                    ),
                                    SizedBox(width: compact ? 12 : 18),
                                    _roundAction(
                                      key: const ValueKey('cast-ctrl-vol-up'),
                                      tooltip: '音量加',
                                      icon: Icons.volume_up_rounded,
                                      compact: compact,
                                      onPressed: () =>
                                          _stepVolume(status.volume, 0.15),
                                    ),
                                  ],
                                ),
                                SizedBox(height: compact ? 4 : 14),
                                SizedBox(
                                  height: compact ? 26 : 34,
                                  child: Row(
                                    children: [
                                      Text(
                                        formatPosition(position),
                                        style: const TextStyle(
                                          color: AppColors.white70,
                                          fontSize: 11.5,
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context)
                                              .copyWith(
                                                trackHeight: 3,
                                                activeTrackColor:
                                                    AppColors.hongguoRed,
                                                inactiveTrackColor: AppColors
                                                    .playerProgressInactive,
                                                thumbColor: AppColors.white,
                                                thumbShape:
                                                    const RoundSliderThumbShape(
                                                  enabledThumbRadius: 6,
                                                ),
                                                overlayShape:
                                                    const RoundSliderOverlayShape(
                                                  overlayRadius: 12,
                                                ),
                                              ),
                                          child: Slider(
                                            key: const ValueKey(
                                              'cast-ctrl-seek',
                                            ),
                                            value: position,
                                            min: 0.0,
                                            max: duration,
                                            onChanged: (val) => setState(
                                              () => _seekValue = val,
                                            ),
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
                                          fontFeatures: [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: compact ? 6 : 12),
                                Wrap(
                                  spacing: compact ? 6 : 10,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _chipAction(
                                      key: const ValueKey('cast-ctrl-rate'),
                                      icon: Icons.speed_rounded,
                                      label: '${_rate}x',
                                      compact: compact,
                                      onPressed: _cycleRate,
                                    ),
                                    _chipAction(
                                      key: const ValueKey('cast-ctrl-episodes'),
                                      icon: Icons.playlist_play_rounded,
                                      label: '选集',
                                      compact: compact,
                                      onPressed: widget.onEpisodes,
                                    ),
                                    _chipAction(
                                      key: const ValueKey('cast-ctrl-switch'),
                                      icon: Icons.devices_rounded,
                                      label: '换设备',
                                      compact: compact,
                                      onPressed: widget.onSwitchDevice,
                                    ),
                                    _chipAction(
                                      key: const ValueKey('cast-ctrl-stop'),
                                      icon: Icons.close_rounded,
                                      label: '退出投屏',
                                      danger: true,
                                      compact: compact,
                                      onPressed: () =>
                                          unawaited(widget.onStopCast()),
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
            );
          },
        ),
      ),
    );
  }
}
