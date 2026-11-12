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

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
    setState(() {
      _currentIndex = index;
    });
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
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _showOfflineEpisodesSheet() {
    _startHideControlsTimer();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E212B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '离线已下载集数',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 180,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: widget.completedJobs.length,
                  itemBuilder: (context, index) {
                    final isCurrent = index == _currentIndex;
                    final job = widget.completedJobs[index];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _switchEpisode(index);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppColors.hongguoRed
                              : const Color(0xFF2B2F3D),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${job.episode.number}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
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

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('offline-player-back'),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.drama.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '第 ${_currentJob.episode.number} 集 · 本地离线播放',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '离线无网络',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final player = _player;
    if (player == null) {
      return _buildBottomBarContent(
        context,
        currentPos: Duration.zero,
        totalDur: Duration.zero,
        isPlaying: false,
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
                return _buildBottomBarContent(
                  context,
                  currentPos: currentPos,
                  totalDur: totalDur,
                  isPlaying: isPlaying,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBottomBarContent(
    BuildContext context, {
    required Duration currentPos,
    required Duration totalDur,
    required bool isPlaying,
  }) {
    final player = _player;
    final totalMs = totalDur.inMilliseconds.toDouble();
    final currentMs = _isSeeking
        ? _seekPositionMs
        : currentPos.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 0.0);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      _formatDuration(Duration(milliseconds: currentMs.toInt())),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.hongguoRed,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: AppColors.hongguoRed,
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: totalMs > 0 ? currentMs.clamp(0.0, totalMs) : 0.0,
                          min: 0.0,
                          max: totalMs > 0 ? totalMs : 1.0,
                          onChangeStart: (_) {
                            _isSeeking = true;
                            _hideControlsTimer?.cancel();
                          },
                          onChanged: (val) {
                            setState(() {
                              _seekPositionMs = val;
                            });
                          },
                          onChangeEnd: (val) {
                            player?.seek(Duration(milliseconds: val.toInt()));
                            _isSeeking = false;
                            _startHideControlsTimer();
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(totalDur),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: () {
                            player?.playOrPause();
                            _startHideControlsTimer();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                          tooltip: '后退 10 秒',
                          onPressed: () {
                            if (player == null) return;
                            final target = player.state.position - const Duration(seconds: 10);
                            player.seek(target < Duration.zero ? Duration.zero : target);
                            _startHideControlsTimer();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                          tooltip: '快进 10 秒',
                          onPressed: () {
                            if (player == null) return;
                            final target = player.state.position + const Duration(seconds: 10);
                            player.seek(target > player.state.duration ? player.state.duration : target);
                            _startHideControlsTimer();
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (widget.completedJobs.length > 1)
                          TextButton.icon(
                            key: const ValueKey('offline-episodes-btn'),
                            onPressed: _showOfflineEpisodesSheet,
                            icon: const Icon(Icons.video_library_outlined, color: Colors.white, size: 18),
                            label: Text(
                              '选集 (${widget.completedJobs.length})',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        IconButton(
                          icon: Icon(
                            _isFullScreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            color: Colors.white,
                          ),
                          tooltip: _isFullScreen ? '退出全屏' : '全屏',
                          onPressed: _toggleFullScreen,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
            _buildTopBar(context),
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
        backgroundColor: Colors.black,
        body: widget.videoBuilder!(context, _buildControls(context)),
      );
    }

    final player = _player!;
    final video = _video!;

    return Scaffold(
      backgroundColor: Colors.black,
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
                                const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  _loadError!,
                                  style: const TextStyle(color: Colors.white70),
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
                        color: Colors.white70,
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
