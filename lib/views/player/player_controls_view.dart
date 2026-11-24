import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/core/player/player_interactions.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/views/player/player_bottom_bar_view.dart';
import 'package:THLRedLook/views/player/player_center_view.dart';
import 'package:THLRedLook/views/player/player_danmaku_button_view.dart';
import 'package:THLRedLook/views/player/player_gesture_hud_overlay.dart';
import 'package:THLRedLook/views/player/player_top_bar_view.dart';

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
    this.onComments,
    this.onDanmaku,
    this.onDanmakuSettings,
    this.onRetryDanmaku,
    this.onPush,
    this.onPictureInPicture,
    this.pictureInPictureRequested = false,
    this.playbackRequested,
    this.enhancement,
    this.isCover = false,
    this.onToggleFit,
    this.landscapeLocked = false,
    this.onToggleLandscapeLock,
  });

  final Player player;
  final bool? playbackRequested;
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
  final Future<void> Function()? onComments;
  final Future<void> Function()? onDanmaku;
  final Future<void> Function()? onDanmakuSettings;
  final Future<void> Function()? onRetryDanmaku;
  final Future<void> Function()? onPush;
  final Future<void> Function()? onPictureInPicture;
  final bool pictureInPictureRequested;
  final VideoEnhancementController? enhancement;
  final bool isCover;
  final VoidCallback? onToggleFit;
  final bool landscapeLocked;
  final VoidCallback? onToggleLandscapeLock;

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
          if (widget.showOnPlaybackReady) {
            _show();
          }
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
    if (!widget.showOnPlaybackReady && oldWidget.showOnPlaybackReady) {
      _hide();
    }
    if (widget.enabled != oldWidget.enabled ||
        widget.panelOpen != oldWidget.panelOpen ||
        widget.fullscreen != oldWidget.fullscreen) {
      _seekValue = null;
      if (widget.enabled && !oldWidget.enabled) {
        if (widget.showOnPlaybackReady) {
          _show();
        } else {
          _hide();
        }
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

  void _hide() {
    _hideTimer?.cancel();
    if (_visible) setState(() => _visible = false);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.player.state.playing || widget.panelOpen) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          _visible &&
          widget.player.state.playing &&
          !widget.panelOpen) {
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
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent && AppLayout.isDesktop(context)) {
                    widget.interactions.handleScrollVolume(event.scrollDelta.dy);
                  }
                },
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
                  child: Semantics(
                    identifier: 'player-surface',
                    label: '显示或隐藏播放控制',
                    button: true,
                  ),
                ),
              ),
              if (state.buffering && widget.enabled)
                Center(
                  child: Transform.translate(
                    offset: const Offset(0, -76),
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(semanticsLabel: '正在缓冲'),
                    ),
                  ),
                ),
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
                      if (widget.enabled)
                        PlayerCenterView(
                          playing: widget.playbackRequested ?? state.playing,
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
                          onTap:
                              widget.enabled &&
                                  (widget.onRetryDanmaku != null ||
                                      widget.onDanmaku != null)
                              ? () => _panel(
                                  widget.onRetryDanmaku ?? widget.onDanmaku!,
                                )
                              : null,
                          onSettings: widget.onDanmakuSettings != null
                              ? () => _panel(widget.onDanmakuSettings!)
                              : null,
                        ),

                      // 底部控制与进度条
                      AnimatedSlide(
                        offset: _visible ? Offset.zero : const Offset(0, 0.4),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: PlayerBottomBarView(
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
                          volume: state.volume,
                          isCover: widget.isCover,
                          onToggleFit: widget.onToggleFit,
                          landscapeLocked: widget.landscapeLocked,
                          onToggleLandscapeLock: widget.onToggleLandscapeLock,
                          onDismiss: _hide,
                          onVolumeChange: widget.enabled
                              ? (val) {
                                  widget.interactions.setVolumeDirect(val);
                                  _show();
                                }
                              : null,
                          onToggleMute: widget.enabled
                              ? () {
                                  widget.interactions.toggleMute();
                                  _show();
                                }
                              : null,
                          onSpeed: () => _panel(widget.onSpeed),
                          onQuality: () => _panel(widget.onQuality),
                          onFullscreen: widget.onFullscreen,
                          onEpisodes: () => _panel(widget.onEpisodes),
                          onComments: widget.onComments != null
                              ? () => _panel(widget.onComments!)
                              : null,
                          onPush: widget.onPush != null
                              ? () => _panel(widget.onPush!)
                              : null,
                          onPictureInPicture: widget.onPictureInPicture != null
                              ? () => _panel(widget.onPictureInPicture!)
                              : null,
                          pictureInPictureRequested:
                              widget.pictureInPictureRequested,
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
                      ),
                    ],
                  ),
                ),
              ),
              PlayerGestureHudOverlay(interactions: widget.interactions),
            ],
          );
        },
      ),
    );
  }
}

