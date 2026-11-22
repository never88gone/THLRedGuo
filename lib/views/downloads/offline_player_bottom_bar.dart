import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

class OfflinePlayerBottomBar extends StatelessWidget {
  const OfflinePlayerBottomBar({
    super.key,
    required this.currentPos,
    required this.totalDur,
    required this.isPlaying,
    required this.isSeeking,
    required this.seekPositionMs,
    required this.isFullScreen,
    required this.episodeCount,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onPlayPause,
    required this.onReplay10,
    required this.onForward10,
    required this.onShowEpisodes,
    required this.onToggleFullScreen,
  });

  final Duration currentPos;
  final Duration totalDur;
  final bool isPlaying;
  final bool isSeeking;
  final double seekPositionMs;
  final bool isFullScreen;
  final int episodeCount;
  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onPlayPause;
  final VoidCallback onReplay10;
  final VoidCallback onForward10;
  final VoidCallback onShowEpisodes;
  final VoidCallback onToggleFullScreen;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = totalDur.inMilliseconds.toDouble();
    final currentMs = isSeeking
        ? seekPositionMs
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
            colors: [AppColors.black80, AppColors.transparent],
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
                      style: const TextStyle(color: AppColors.white70, fontSize: 12),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.hongguoRed,
                          inactiveTrackColor: AppColors.white24,
                          thumbColor: AppColors.hongguoRed,
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: totalMs > 0 ? currentMs.clamp(0.0, totalMs) : 0.0,
                          min: 0.0,
                          max: totalMs > 0 ? totalMs : 1.0,
                          onChangeStart: (_) => onSeekStart(),
                          onChanged: onSeekChanged,
                          onChangeEnd: onSeekEnd,
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(totalDur),
                      style: const TextStyle(color: AppColors.white70, fontSize: 12),
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
                            color: AppColors.white,
                            size: 32,
                          ),
                          onPressed: onPlayPause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded, color: AppColors.white),
                          tooltip: '后退 10 秒',
                          onPressed: onReplay10,
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded, color: AppColors.white),
                          tooltip: '快进 10 秒',
                          onPressed: onForward10,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (episodeCount > 1)
                          TextButton.icon(
                            key: const ValueKey('offline-episodes-btn'),
                            onPressed: onShowEpisodes,
                            icon: const Icon(
                              Icons.video_library_outlined,
                              color: AppColors.white,
                              size: 18,
                            ),
                            label: Text(
                              '选集 ($episodeCount)',
                              style: const TextStyle(color: AppColors.white),
                            ),
                          ),
                        IconButton(
                          icon: Icon(
                            isFullScreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            color: AppColors.white,
                          ),
                          tooltip: isFullScreen ? '退出全屏' : '全屏',
                          onPressed: onToggleFullScreen,
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
}
