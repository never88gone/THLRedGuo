import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../app_colors.dart';
import '../../player_interactions.dart';
import '../../video_enhancement.dart';
import '../../widgets.dart';
import 'player_bottom_bar_view.dart';
import 'player_center_view.dart';
import 'player_danmaku_button_view.dart';
import 'player_top_bar_view.dart';

/// 播放器主控制覆盖层（聚合手势、自动隐藏、顶栏、底栏、居中动作与弹幕）
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.interactions,
    required this.enabled,
    required this.fullscreen,
    required this.showOnPlaybackReady,
    required this.onFullscreen,
    required this.onBack,
    required this.onPrevious,
    required this.onNext,
    required this.title,
    required this.onTogglePlayback,
    required this.onEpisodes,
    required this.onSpeed,
    required this.onQuality,
    required this.speed,
    required this.qualityLabel,
    required this.onFocusSurface,
    this.showDanmaku = false,
    this.danmakuEnabled = false,
    this.danmakuStatus = '',
    this.swipeEnabled = false,
    this.panelOpen = false,
    this.onSeek,
    this.onDanmaku,
    this.onRetryDanmaku,
    this.onPush,
    this.onPictureInPicture,
    this.enhancement,
  });

  final Player player;
  final PlayerInteractions interactions;
  final bool enabled;
  final bool fullscreen;
  final bool showOnPlaybackReady;
  final VoidCallback onFullscreen;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String title;
  final VoidCallback onTogglePlayback;
  final Future<void> Function() onEpisodes;
  final Future<void> Function() onSpeed;
  final Future<void> Function() onQuality;
  final double speed;
  final String qualityLabel;
  final VoidCallback onFocusSurface;
  final bool showDanmaku;
  final bool danmakuEnabled;
  final String danmakuStatus;
  final bool swipeEnabled;
  final bool panelOpen;
  final Future<void> Function(Duration)? onSeek;
  final Future<void> Function()? onDanmaku;
  final Future<void> Function()? onRetryDanmaku;
  final Future<void> Function()? onPush;
  final Future<void> Function()? onPictureInPicture;
  final VideoEnhancementController? enhancement;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _hideTimer;
  bool _visible = true;
  double? _seekValue;

  @override
  void initState() {
    super.initState();
    _visible = widget.showOnPlaybackReady;
    for (final stream in [
      widget.player.stream.position,
      widget.player.stream.duration,
      widget.player.stream.buffer,
      widget.player.stream.playing,
      widget.player.stream.buffering,
      widget.player.stream.volume,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          if (mounted) setState(() {});
        }),
      );
    }
    _subscriptions.add(
      widget.player.stream.playing.listen((playing) {
        if (!mounted || !widget.enabled) return;
        if (!playing) {
          _show();
        } else {
          _scheduleHide();
        }
      }),
    );
    _scheduleHide();
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled ||
        widget.panelOpen != oldWidget.panelOpen ||
        widget.fullscreen != oldWidget.fullscreen) {
      _seekValue = null;
      if (widget.enabled && !oldWidget.enabled) {
        _show();
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  void _show() {
    _hideTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.player.state.playing || widget.panelOpen) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _visible && widget.player.state.playing && !widget.panelOpen) {
        setState(() => _visible = false);
      }
    });
  }

  void _toggleVisibility() {
    if (_visible) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    } else {
      _show();
    }
  }

  Future<void> _panel(Future<void> Function() open) async {
    _hideTimer?.cancel();
    widget.interactions.cancel();
    await open();
    if (mounted) _show();
  }

  Future<void> _seekTo(Duration duration) async {
    if (widget.onSeek != null) {
      await widget.onSeek!(duration);
    } else {
      await widget.player.seek(duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.player.state;
    final duration = state.duration.inMilliseconds > 0
        ? state.duration.inMilliseconds / 1000
        : 0.0;
    final position = state.position.inMilliseconds > 0
        ? state.position.inMilliseconds / 1000
        : 0.0;
    final buffered = state.buffer.inMilliseconds > 0
        ? state.buffer.inMilliseconds / 1000
        : 0.0;

    return Focus(
      autofocus: false,
      canRequestFocus: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = widget.swipeEnabled && !widget.fullscreen;
          return Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                key: const ValueKey('player-gesture-surface'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  widget.onFocusSurface();
                  widget.interactions.pointerDown(
                    event,
                    swipeEnabled: widget.swipeEnabled,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  );
                },
                onPointerMove: widget.interactions.pointerMove,
                onPointerUp: widget.interactions.pointerUp,
                onPointerCancel: widget.interactions.pointerCancel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onFocusSurface();
                    _toggleVisibility();
                  },
                  onDoubleTap: () {
                    widget.onFocusSurface();
                    widget.onTogglePlayback();
                    _show();
                  },
                ),
              ),
              if (state.buffering && widget.enabled)
                const Center(child: CircularProgressIndicator()),
              AnimatedOpacity(
                opacity: _visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  ignoring: !_visible,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.playerMaskTop,
                                AppColors.transparent,
                                AppColors.playerMaskBottom,
                              ],
                              stops: [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ),

                        // 顶部导航栏
                        PlayerTopBarView(
                          title: widget.title,
                          fullscreen: widget.fullscreen,
                          compact: compact,
                          onBack: widget.onBack,
                          onFullscreen: widget.onFullscreen,
                        ),

                        // 中央大播放/切集控制
                        if (!state.buffering && widget.enabled)
                          PlayerCenterView(
                            playing: state.playing,
                            showSkip: true,
                            onTogglePlayback: () {
                              widget.onTogglePlayback();
                              _show();
                            },
                            onPrevious: widget.onPrevious,
                            onNext: widget.onNext,
                          ),

                        // 右上方轻量弹幕开关（避让中央按键）
                        if (widget.showDanmaku)
                          PlayerDanmakuButtonView(
                            enabled: widget.enabled,
                            danmakuEnabled: widget.danmakuEnabled,
                            danmakuStatus: widget.danmakuStatus,
                            swipeEnabled: widget.swipeEnabled,
                            canRetry: widget.onRetryDanmaku != null,
                            onTap: widget.enabled && (widget.onRetryDanmaku != null || widget.onDanmaku != null)
                                ? () => _panel(widget.onRetryDanmaku ?? widget.onDanmaku!)
                                : null,
                          ),

                        // 底部控制与进度条
                        PlayerBottomBarView(
                          constraints: constraints,
                          fullscreen: widget.fullscreen,
                          swipeEnabled: widget.swipeEnabled,
                          enabled: widget.enabled,
                          speed: widget.speed,
                          qualityLabel: widget.qualityLabel,
                          duration: duration,
                          position: position,
                          buffered: buffered,
                          seekValue: _seekValue,
                          onSpeed: () => _panel(widget.onSpeed),
                          onQuality: () => _panel(widget.onQuality),
                          onFullscreen: widget.onFullscreen,
                          onEpisodes: () => _panel(widget.onEpisodes),
                          onPush: widget.onPush != null ? () => _panel(widget.onPush!) : null,
                          onPictureInPicture: widget.onPictureInPicture != null
                              ? () => _panel(widget.onPictureInPicture!)
                              : null,
                          onSeekStart: (_) {
                            _hideTimer?.cancel();
                          },
                          onSeekChange: (val) {
                            _hideTimer?.cancel();
                            setState(() => _seekValue = val);
                          },
                          onSeekEnd: (val) {
                            _seekTo(Duration(milliseconds: (val * 1000).toInt()));
                            setState(() => _seekValue = null);
                            _scheduleHide();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                _GestureHudOverlay(interactions: widget.interactions),
              ],
            );
          },
        ),
      );
  }
}

class _GestureHudOverlay extends StatelessWidget {
  const _GestureHudOverlay({required this.interactions});

  final PlayerInteractions interactions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: interactions,
      builder: (context, _) {
        final hud = interactions.hudState;
        if (hud.type == SwipeAction.none) {
          return const SizedBox.shrink();
        }

        return IgnorePointer(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: hud.type == SwipeAction.seek
                  ? _buildSeekCard(hud)
                  : hud.type == SwipeAction.brightness
                      ? _buildBrightnessCard(hud)
                      : const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeekCard(GestureHudState hud) {
    final isForward = hud.deltaSeconds >= 0;
    final totalSec = hud.duration.inSeconds.toDouble();
    final posSec = hud.position.inSeconds.toDouble().clamp(0.0, totalSec > 0 ? totalSec : 0.0);
    final ratio = totalSec > 0 ? (posSec / totalSec).clamp(0.0, 1.0) : 0.0;
    final sign = hud.deltaSeconds > 0 ? '+' : '';

    return Container(
      key: const ValueKey('seek-hud-card'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.playerGestureHudBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.playerGestureHudBorder,
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.playerGestureHudShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                color: AppColors.white,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                '$sign${hud.deltaSeconds}s',
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatPosition(posSec),
                style: const TextStyle(
                  color: AppColors.playerGestureHudHighlight,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                ' / ${formatPosition(totalSec)}',
                style: const TextStyle(
                  color: AppColors.playerGestureHudTextSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 3.5,
                backgroundColor: AppColors.playerGestureHudTrack,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.playerGestureHudHighlight),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrightnessCard(GestureHudState hud) {
    final percent = (hud.value * 100).round().clamp(0, 100);
    return Container(
      key: const ValueKey('brightness-hud-card'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.playerGestureHudBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.playerGestureHudBorder,
          width: 0.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.playerGestureHudShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hud.value > 0.5 ? Icons.brightness_7_rounded : Icons.brightness_medium_rounded,
            color: AppColors.white,
            size: 26,
          ),
          const SizedBox(height: 6),
          Text(
            '$percent%',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: hud.value.clamp(0.0, 1.0),
                minHeight: 3.5,
                backgroundColor: AppColors.playerGestureHudTrack,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

