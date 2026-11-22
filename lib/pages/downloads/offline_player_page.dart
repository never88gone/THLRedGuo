import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/downloads/offline_episodes_sheet.dart';
import 'package:THLRedLook/views/downloads/offline_player_bottom_bar.dart';
import 'package:THLRedLook/views/downloads/offline_player_top_bar.dart';

class OfflinePlayerPage extends StatefulWidget {
  const OfflinePlayerPage({
    super.key,
    required this.drama,
    required this.completedJobs,
    required this.initialIndex,
    required this.repository,
    required this.store,
    @visibleForTesting this.player,
    @visibleForTesting this.videoBuilder,
  });

  final Drama drama;
  final List<DownloadJob> completedJobs;
  final int initialIndex;
  final AppRepository repository;
  final LocalStore store;
  final Player? player;
  final Widget Function(BuildContext context, Widget controls)? videoBuilder;

  @override
  State<OfflinePlayerPage> createState() => _OfflinePlayerPageState();
}

class _OfflinePlayerPageState extends State<OfflinePlayerPage> {
  late int _currentIndex;
  Player? _player;
  VideoController? _video;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _hideControlsTimer;
  bool _controlsVisible = true;
  bool _isSeeking = false;
  double _seekPositionMs = 0;
  bool _isFullScreen = false;
  String? _loadError;
  bool _loading = true;

  DownloadJob get _currentJob => widget.completedJobs[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.completedJobs.length - 1);
    if (widget.videoBuilder == null) {
      _player = widget.player ??
          Player(
            configuration: const PlayerConfiguration(
              logLevel: MPVLogLevel.error,
            ),
          );
      _video = VideoController(
        _player!,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: !Platform.isIOS,
          hwdec: Platform.isWindows ? 'auto-copy-safe' : 'auto-safe',
        ),
      );
      _initPlayback();
    } else {
      _loading = false;
    }
    _startHideControlsTimer();
  }

  Future<void> _initPlayback() async {
    final player = _player;
    if (player == null) return;
    final job = _currentJob;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final plan = await widget.repository.localPlayback(widget.drama, job.episode);
      if (plan == null || !plan.local || plan.url.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _loadError = '未找到已下载的离线视频文件';
          });
        }
        return;
      }

      final watched = widget.store.watched(widget.drama.id);
      final resumeMs = (watched != null && watched.episode == job.episode.number && !watched.finished)
          ? (watched.position * 1000).toInt()
          : 0;

      await player.open(Media(plan.url));
      if (resumeMs > 0 && mounted) {
        await player.seek(Duration(milliseconds: resumeMs));
      }

      _completedSub?.cancel();
      _completedSub = player.stream.completed.listen((completed) {
        if (completed && mounted) {
          if (_currentIndex + 1 < widget.completedJobs.length) {
            _switchEpisode(_currentIndex + 1);
          }
        }
      });

      _positionSub?.cancel();
      _positionSub = player.stream.position.listen((pos) {
        if (!_isSeeking && mounted && player.state.duration.inMilliseconds > 0) {
          final totalSec = player.state.duration.inSeconds.toDouble();
          final posSec = pos.inSeconds.toDouble();
          if (totalSec > 0) {
            widget.store.saveWatch(
              WatchEntry(
                drama: widget.drama,
                episode: _currentJob.episode.number,
                position: posSec,
                duration: totalSec,
                updatedAt: DateTime.now(),
              ),
            );
          }
        }
      });

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '加载离线视频失败: $e';
        });
      }
    }
  }

  void _switchEpisode(int index) {
    if (index < 0 || index >= widget.completedJobs.length) return;
    setState(() => _currentIndex = index);
    _initPlayback();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _player?.state.playing == true && !_isSeeking) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _showOfflineEpisodes() {
    _startHideControlsTimer();
    OfflineEpisodesSheet.show(
      context: context,
      completedJobs: widget.completedJobs,
      currentIndex: _currentIndex,
      onSelectEpisode: _switchEpisode,
    );
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _completedSub?.cancel();
    _positionSub?.cancel();
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _player?.dispose();
    super.dispose();
  }

  Widget _buildBottomBar(BuildContext context) {
    final player = _player;
    if (player == null) {
      return OfflinePlayerBottomBar(
        currentPos: Duration.zero,
        totalDur: Duration.zero,
        isPlaying: false,
        isSeeking: _isSeeking,
        seekPositionMs: _seekPositionMs,
        isFullScreen: _isFullScreen,
        episodeCount: widget.completedJobs.length,
        onSeekStart: () {
          _isSeeking = true;
          _hideControlsTimer?.cancel();
        },
        onSeekChanged: (val) => setState(() => _seekPositionMs = val),
        onSeekEnd: (val) {
          player?.seek(Duration(milliseconds: val.toInt()));
          _isSeeking = false;
          _startHideControlsTimer();
        },
        onPlayPause: () {},
        onReplay10: () {},
        onForward10: () {},
        onShowEpisodes: _showOfflineEpisodes,
        onToggleFullScreen: _toggleFullScreen,
      );
    }

    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, posSnapshot) {
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          builder: (context, durSnapshot) {
            final currentPos = posSnapshot.data ?? player.state.position;
            final totalDur = durSnapshot.data ?? player.state.duration;
            return StreamBuilder<bool>(
              stream: player.stream.playing,
              builder: (context, playingSnap) {
                final isPlaying = playingSnap.data ?? player.state.playing;
                return OfflinePlayerBottomBar(
                  currentPos: currentPos,
                  totalDur: totalDur,
                  isPlaying: isPlaying,
                  isSeeking: _isSeeking,
                  seekPositionMs: _seekPositionMs,
                  isFullScreen: _isFullScreen,
                  episodeCount: widget.completedJobs.length,
                  onSeekStart: () {
                    _isSeeking = true;
                    _hideControlsTimer?.cancel();
                  },
                  onSeekChanged: (val) => setState(() => _seekPositionMs = val),
                  onSeekEnd: (val) {
                    player.seek(Duration(milliseconds: val.toInt()));
                    _isSeeking = false;
                    _startHideControlsTimer();
                  },
                  onPlayPause: () {
                    player.playOrPause();
                    _startHideControlsTimer();
                  },
                  onReplay10: () {
                    final target = player.state.position - const Duration(seconds: 10);
                    player.seek(target < Duration.zero ? Duration.zero : target);
                    _startHideControlsTimer();
                  },
                  onForward10: () {
                    final target = player.state.position + const Duration(seconds: 10);
                    player.seek(target > player.state.duration ? player.state.duration : target);
                    _startHideControlsTimer();
                  },
                  onShowEpisodes: _showOfflineEpisodes,
                  onToggleFullScreen: _toggleFullScreen,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildControls(BuildContext context) {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OfflinePlayerTopBar(
              drama: widget.drama,
              episodeNumber: _currentJob.episode.number,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videoBuilder != null) {
      return Scaffold(
        backgroundColor: AppColors.black,
        body: widget.videoBuilder!(context, _buildControls(context)),
      );
    }

    final player = _player!;
    final video = _video!;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: GestureDetector(
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: _loading
                    ? const CircularProgressIndicator(color: AppColors.hongguoRed)
                    : _loadError != null
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.white54, size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  _loadError!,
                                  style: const TextStyle(color: AppColors.white70),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _initPlayback,
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.hongguoRed),
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          )
                        : Video(
                            controller: video,
                            controls: NoVideoControls,
                          ),
              ),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (context, playingSnapshot) {
                  final isPlaying = playingSnapshot.data ?? player.state.playing;
                  if (!isPlaying && !_controlsVisible && !_loading && _loadError == null) {
                    return Center(
                      child: IconButton(
                        iconSize: 64,
                        color: AppColors.white70,
                        icon: const Icon(Icons.play_circle_fill_rounded),
                        onPressed: () {
                          player.play();
                          _startHideControlsTimer();
                        },
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              _buildControls(context),
            ],
          ),
        ),
      ),
    );
  }
}
