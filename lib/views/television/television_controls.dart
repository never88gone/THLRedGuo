import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/core/player/playback_diagnostics.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/views/remote/remote_widgets.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

export 'television_episode_dialog.dart';
export 'television_settings_dialog.dart';

class TelevisionControls extends StatefulWidget {
  const TelevisionControls({
    super.key,
    required this.player,
    required this.title,
    required this.enabled,
    required this.showOnPlaybackReady,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onPrevious,
    required this.onNext,
    required this.onEpisodes,
    required this.onSettings,
    required this.onBack,
    this.enhancement,
    this.onFetchDiagnostics,
  });
  final Player player;
  final String title;
  final bool enabled;
  final bool showOnPlaybackReady;
  final VoidCallback onTogglePlayback;
  final ValueChanged<int> onSeek;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Future<void> Function() onEpisodes;
  final Future<void> Function() onSettings;
  final VoidCallback onBack;
  final VideoEnhancementController? enhancement;
  final Future<PlaybackTechnicalDiagnostics?> Function()? onFetchDiagnostics;

  @override
  State<TelevisionControls> createState() => _TelevisionControlsState();
}

class _TelevisionControlsState extends State<TelevisionControls> {
  final _surface = FocusNode(debugLabel: 'tv-player-surface');
  final _play = FocusNode(debugLabel: 'tv-player-play');
  final _episodes = FocusNode(debugLabel: 'tv-player-episodes');
  final _diary = FocusNode(debugLabel: 'tv-player-diary');
  final _settings = FocusNode(debugLabel: 'tv-player-settings');
  final _progress = FocusNode(debugLabel: 'tv-player-progress');
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _hideTimer;
  Timer? _seekTimer;
  Timer? _hudTimer;
  String? _hudMessage;
  bool _visible = true;
  bool _panelOpen = false;
  bool _seekHint = false;

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
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          if (!mounted) return;
          setState(() {});
        }),
      );
    }
    _subscriptions.add(
      widget.player.stream.playing.listen((playing) {
        if (!mounted || !widget.enabled || _panelOpen) return;
        if (playing) {
          _scheduleHide();
        } else if (widget.showOnPlaybackReady && _visible) {
          _show();
        }
      }),
    );
    if (widget.enabled) {
      if (widget.showOnPlaybackReady) {
        _show();
      } else {
        _visible = false;
        _focus(_surface);
      }
    }
  }

  @override
  void didUpdateWidget(covariant TelevisionControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      if (widget.showOnPlaybackReady) {
        _show();
      } else {
        setState(() => _visible = false);
        _hideTimer?.cancel();
        _focus(_surface);
      }
    } else if (!widget.enabled) {
      _hideTimer?.cancel();
    }
  }

  void _focus(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.enabled &&
          !_panelOpen &&
          node.context != null &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        node.requestFocus();
      }
    });
  }

  void _show() {
    final needsFocus =
        !_visible || !_surface.hasFocus || _surface.hasPrimaryFocus;
    if (!_visible) setState(() => _visible = true);
    if (needsFocus) _focus(_play);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.enabled || _panelOpen) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted &&
          widget.enabled &&
          !_panelOpen &&
          widget.player.state.playing) {
        setState(() => _visible = false);
        if (_surface.hasFocus) _focus(_surface);
      }
    });
  }

  void _seek(int seconds) {
    widget.onSeek(seconds);
    setState(() => _seekHint = true);
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _seekHint = false);
    });
    _scheduleHide();
  }

  void _showHud(String message) {
    _hudTimer?.cancel();
    setState(() => _hudMessage = message);
    _hudTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _hudMessage = null);
    });
  }

  Future<void> _openPanel(
    Future<void> Function() action,
    FocusNode returnFocus,
  ) async {
    if (_panelOpen) return;
    _panelOpen = true;
    _hideTimer?.cancel();
    try {
      await action();
    } finally {
      if (mounted) {
        _panelOpen = false;
        if (widget.enabled) {
          setState(() => _visible = true);
          _focus(returnFocus);
          _scheduleHide();
        }
      }
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (!widget.enabled ||
        _panelOpen ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    _scheduleHide();
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) widget.onBack();
    } else if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        widget.onTogglePlayback();
        _show();
      }
    } else if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      if (event is KeyDownEvent &&
          widget.player.state.playing !=
              (key == LogicalKeyboardKey.mediaPlay)) {
        widget.onTogglePlayback();
        _show();
      }
    } else if (key == LogicalKeyboardKey.mediaTrackNext) {
      if (event is KeyDownEvent) widget.onNext?.call();
    } else if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (event is KeyDownEvent) widget.onPrevious?.call();
    } else if ((!_visible || _progress.hasFocus) &&
        key == LogicalKeyboardKey.arrowLeft) {
      _seek(-10);
    } else if ((!_visible || _progress.hasFocus) &&
        key == LogicalKeyboardKey.arrowRight) {
      _seek(10);
    } else if ((!_visible || _surface.hasPrimaryFocus) &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      if (event is KeyDownEvent) {
        if (key == LogicalKeyboardKey.arrowUp) {
          if (widget.onPrevious != null) {
            widget.onPrevious!();
            _showHud('上一集');
          } else {
            _showHud('已是第一集');
          }
        } else {
          if (widget.onNext != null) {
            widget.onNext!();
            _showHud('下一集');
          } else {
            _showHud('已是最后一集');
          }
        }
      }
    } else if ((!_visible || _surface.hasPrimaryFocus) &&
        [
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.gameButtonA,
          LogicalKeyboardKey.contextMenu,
        ].contains(key)) {
      _show();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekTimer?.cancel();
    _hudTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    for (final node in [_surface, _play, _episodes, _diary, _settings, _progress]) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.player.state;
    final duration = state.duration.inMilliseconds / 1000;
    final position = state.position.inMilliseconds / 1000;
    return ExcludeFocus(
      excluding: !widget.enabled,
      child: Focus(
        focusNode: _surface,
        onKeyEvent: _key,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? _show : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (state.buffering && widget.enabled)
                const Center(child: CircularProgressIndicator()),
              if ((_seekHint || _hudMessage != null) && !_visible)
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.blackWithAlpha(0.87),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      child: Text(
                        _hudMessage ?? '${formatPosition(position)} / ${formatPosition(duration)}',
                        style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              if (_visible && widget.enabled) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.playerMaskTop, AppColors.transparent, AppColors.playerMaskBottom],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 24,
                  right: 24,
                  child: Row(
                    children: [
                      RemoteButton(
                        key: const ValueKey('tv-player-back'),
                        label: '返回',
                        icon: Icons.arrow_back_rounded,
                        onPressed: widget.onBack,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: 18,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RemoteTarget(
                        key: const ValueKey('tv-progress'),
                        label: '播放进度，左右键快进或后退十秒',
                        focusNode: _progress,
                        onPressed: widget.onTogglePlayback,
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                LinearProgressIndicator(
                                  value: duration > 0 ? (state.buffer.inMilliseconds / 1000 / duration).clamp(0, 1) : 0,
                                  minHeight: 5,
                                  color: AppColors.playerProgressBuffered,
                                  backgroundColor: AppColors.playerProgressInactive,
                                ),
                                LinearProgressIndicator(
                                  value: duration > 0 ? (position / duration).clamp(0, 1) : 0,
                                  minHeight: 5,
                                  backgroundColor: AppColors.transparent,
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text('${formatPosition(position)} / ${formatPosition(duration)}', style: const TextStyle(fontSize: 16)),
                                const Spacer(),
                                Text('左右快进 · 确认暂停', style: TextStyle(fontSize: 14, color: AppColors.whiteWithAlpha(0.7))),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            RemoteButton(
                              key: const ValueKey('tv-previous'),
                              label: '上一集',
                              icon: Icons.skip_previous_rounded,
                              onPressed: widget.onPrevious,
                            ),
                            RemoteButton(
                              key: const ValueKey('tv-play-pause'),
                              label: state.playing ? '暂停' : '播放',
                              icon: state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              focusNode: _play,
                              onPressed: () {
                                widget.onTogglePlayback();
                                _scheduleHide();
                              },
                            ),
                            RemoteButton(
                              key: const ValueKey('tv-next'),
                              label: '下一集',
                              icon: Icons.skip_next_rounded,
                              onPressed: widget.onNext,
                            ),
                            RemoteButton(
                              key: const ValueKey('tv-episodes'),
                              label: '选集',
                              icon: Icons.grid_view_rounded,
                              focusNode: _episodes,
                              onPressed: () => _openPanel(widget.onEpisodes, _episodes),
                            ),
                            RemoteButton(
                              key: const ValueKey('tv-diary'),
                              label: '播放日记',
                              icon: Icons.receipt_long_rounded,
                              focusNode: _diary,
                              onPressed: () async {
                                _hideTimer?.cancel();
                                setState(() => _panelOpen = true);
                                await DiaryService.showDiaryDialog(
                                  context,
                                  fetchDiagnostics: widget.onFetchDiagnostics,
                                );
                                if (mounted) {
                                  setState(() => _panelOpen = false);
                                  _focus(_diary);
                                  _scheduleHide();
                                }
                              },
                            ),
                            if (widget.enhancement != null)
                              AnimatedBuilder(
                                animation: widget.enhancement!,
                                builder: (_, _) {
                                  final enhancement = widget.enhancement!;
                                  if (!enhancement.canCompare) return const SizedBox.shrink();
                                  return RemoteButton(
                                    key: const ValueKey('tv-enhancement-compare'),
                                    label: enhancement.comparing ? '恢复增强' : '原画对比',
                                    icon: Icons.compare_rounded,
                                    onPressed: () {
                                      unawaited(enhancement.toggleCompare());
                                      _focus(_play);
                                      _scheduleHide();
                                    },
                                  );
                                },
                              ),
                            RemoteButton(
                              key: const ValueKey('tv-settings'),
                              label: '播放设置',
                              icon: Icons.tune_rounded,
                              focusNode: _settings,
                              onPressed: () => _openPanel(widget.onSettings, _settings),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '控制条隐藏时：上/下键切集，左/右键快退快进，确认键呼出控制条',
                        style: TextStyle(fontSize: 13, color: AppColors.whiteWithAlpha(0.7)),
                      ),
                    ],
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

