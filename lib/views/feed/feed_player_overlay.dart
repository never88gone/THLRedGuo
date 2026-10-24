import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

class FeedPlayerOverlay extends StatelessWidget {
  const FeedPlayerOverlay({
    super.key,
    required this.title,
    required this.episodeText,
    required this.description,
    required this.playing,
    required this.enabled,
    required this.following,
    required this.danmakuEnabled,
    required this.position,
    required this.duration,
    required this.onTogglePlayback,
    required this.onSeek,
    required this.onFavorite,
    required this.onEpisodes,
    required this.onDetail,
    required this.onDanmaku,
    required this.onSettings,
  });

  final String title;
  final String episodeText;
  final String description;
  final bool playing;
  final bool enabled;
  final bool following;
  final bool danmakuEnabled;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlayback;
  final ValueChanged<double> onSeek;
  final VoidCallback onFavorite;
  final VoidCallback onEpisodes;
  final VoidCallback onDetail;
  final VoidCallback onDanmaku;
  final VoidCallback onSettings;

  Widget _action(String id, IconData icon, String label, VoidCallback action) =>
      IconButton(
        key: ValueKey('feed-$id'),
        tooltip: label,
        onPressed: action,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color(0x55000000),
          minimumSize: const Size(48, 48),
        ),
        icon: Icon(icon, size: 27),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 480;
      final actions = [
        _action(
          'favorite',
          following ? Icons.bookmark : Icons.bookmark_border,
          following ? '已追剧' : '加入追剧',
          onFavorite,
        ),
        _action('episodes', Icons.video_library_outlined, '选集', onEpisodes),
        _action(
          'danmaku',
          danmakuEnabled ? Icons.subtitles : Icons.subtitles_off,
          danmakuEnabled ? '关闭弹幕' : '开启弹幕',
          onDanmaku,
        ),
        _action('detail', Icons.info_outline, '剧集详情', onDetail),
        _action('settings', Icons.tune, '播放设置', onSettings),
      ];
      final progress = duration.inMilliseconds > 0
          ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const ValueKey('feed-play-surface'),
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onTogglePlayback : null,
            child: Center(
              child: !playing && enabled
                  ? const Icon(
                      Icons.play_arrow_rounded,
                      size: 76,
                      color: Colors.white70,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          // 底部暗色渐变（仅作视觉层次，不拦截任何触控事件）
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 260,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD9000000)],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              key: const ValueKey('feed-title'),
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              key: const ValueKey('feed-current-episode'),
                              onPressed: onEpisodes,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                alignment: Alignment.centerLeft,
                              ),
                              icon: const Icon(
                                Icons.play_circle_outline,
                                size: 18,
                              ),
                              label: Text(
                                episodeText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!compact && description.isNotEmpty)
                              Text(
                                description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final action in actions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: action,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  if (compact)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: actions,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FeedProgress(
              key: const ValueKey('feed-progress'),
              value: progress,
              onSeek: enabled && duration > Duration.zero ? onSeek : null,
            ),
          ),
        ],
      );
    },
  );
}

class _FeedProgress extends StatefulWidget {
  const _FeedProgress({super.key, required this.value, this.onSeek});
  final double value;
  final ValueChanged<double>? onSeek;

  @override
  State<_FeedProgress> createState() => _FeedProgressState();
}

class _FeedProgressState extends State<_FeedProgress> {
  double? _dragging;

  void _updateSeek(double localDx, double totalWidth) {
    if (widget.onSeek == null || totalWidth <= 0) return;
    final progress = (localDx / totalWidth).clamp(0.0, 1.0);
    setState(() => _dragging = progress);
  }

  void _finishSeek() {
    final target = _dragging;
    setState(() => _dragging = null);
    if (target != null && widget.onSeek != null) {
      widget.onSeek!(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveValue = (_dragging ?? widget.value).clamp(0.0, 1.0);
    final isInteractive = widget.onSeek != null;
    final isDragging = _dragging != null;
    final trackHeight = isDragging ? 4.0 : 2.5;

    return Semantics(
      slider: true,
      enabled: isInteractive,
      value: '${(effectiveValue * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final progressWidth = width * effectiveValue;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: isInteractive
                ? (d) => _updateSeek(d.localPosition.dx, width)
                : null,
            onTapUp: isInteractive ? (_) => _finishSeek() : null,
            onTapCancel:
                isInteractive ? () => setState(() => _dragging = null) : null,
            onHorizontalDragStart: isInteractive
                ? (d) => _updateSeek(d.localPosition.dx, width)
                : null,
            onHorizontalDragUpdate: isInteractive
                ? (d) => _updateSeek(d.localPosition.dx, width)
                : null,
            onHorizontalDragEnd: isInteractive ? (_) => _finishSeek() : null,
            onHorizontalDragCancel:
                isInteractive ? () => setState(() => _dragging = null) : null,
            child: SizedBox(
              height: 20,
              width: width,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  height: trackHeight,
                  width: width,
                  decoration: BoxDecoration(
                    color: AppColors.whiteWithAlpha(0.24),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 播放进度渐变单线（左右顶到屏幕边缘）
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: progressWidth,
                          height: trackHeight,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                AppColors.hongguoOrange,
                                AppColors.hongguoRed,
                                AppColors.hongguoRedLight,
                              ],
                            ),
                            boxShadow: isDragging
                                ? [
                                    BoxShadow(
                                      color:
                                          AppColors.hongguoRedWithAlpha(0.6),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                      // 拖拽手势响应指示微点（静止播放时不显示任何滑块，仅在拖拽微调时给用户清晰反馈）
                      if (isDragging && progressWidth > 0)
                        Positioned(
                          left: (progressWidth - 5).clamp(0.0, width - 10),
                          top: (trackHeight - 10) / 2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.hongguoRedWithAlpha(0.8),
                                  blurRadius: 6,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

void feedPreviewAction() {}
void feedPreviewSeek(double value) {}

@Preview(name: '推荐视频流 · 手机', size: Size(390, 720))
@Preview(name: '推荐视频流 · 横屏', size: Size(740, 350))
Widget feedPlayerPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: ColoredBox(
    color: const Color(0xFF172433),
    child: FeedPlayerOverlay(
      title: '合成短剧：山海来信',
      episodeText: '第 3 集 · 共 60 集',
      description: '一封迟来的信，让一段尘封往事重新展开。',
      playing: true,
      enabled: true,
      following: false,
      danmakuEnabled: true,
      position: const Duration(seconds: 26),
      duration: const Duration(minutes: 2),
      onTogglePlayback: feedPreviewAction,
      onSeek: feedPreviewSeek,
      onFavorite: feedPreviewAction,
      onEpisodes: feedPreviewAction,
      onDetail: feedPreviewAction,
      onDanmaku: feedPreviewAction,
      onSettings: feedPreviewAction,
    ),
  ),
);
