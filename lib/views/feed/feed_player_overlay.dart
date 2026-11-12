import 'package:flutter/material.dart';

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
    this.onSocial,
    this.isLiked = false,
    this.likeCount = 0,
    this.onLike,
    this.anchorName = '',
    this.isAnchorFollowed = false,
    this.onToggleFollowAnchor,
    this.onOpenAnchorDetail,
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
  final VoidCallback? onSocial;

  final bool isLiked;
  final int likeCount;
  final VoidCallback? onLike;
  final String anchorName;
  final bool isAnchorFollowed;
  final VoidCallback? onToggleFollowAnchor;
  final VoidCallback? onOpenAnchorDetail;

  Widget _action(
    String id,
    IconData icon,
    String label,
    VoidCallback action, {
    Color color = Colors.white,
    String? subText,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('feed-$id'),
              tooltip: label,
              onPressed: action,
              style: IconButton.styleFrom(
                foregroundColor: color,
                backgroundColor: const Color(0x55000000),
                minimumSize: const Size(48, 48),
              ),
              icon: Icon(icon, size: 27, color: color),
            ),
            if (subText != null && subText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 4),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 480;
      final effectiveAnchor = anchorName.isNotEmpty ? anchorName : '精选短剧';
      final actions = [
        if (onLike != null)
          _action(
            'like',
            isLiked ? Icons.favorite : Icons.favorite_border,
            isLiked ? '取消点赞' : '点赞',
            onLike!,
            color: isLiked ? AppColors.hongguoRed : Colors.white,
            subText: likeCount > 0 ? '$likeCount' : '点赞',
          )
        else if (onSocial != null)
          _action('social', Icons.favorite_border, '点赞与关注', onSocial!),
        _action(
          'favorite',
          following ? Icons.bookmark : Icons.bookmark_border,
          following ? '已追剧' : '加入追剧',
          onFavorite,
          subText: following ? '已追剧' : '追剧',
        ),
        _action('episodes', Icons.video_library_outlined, '选集', onEpisodes, subText: '选集'),
        _action(
          'danmaku',
          danmakuEnabled ? Icons.subtitles : Icons.subtitles_off,
          danmakuEnabled ? '关闭弹幕' : '开启弹幕',
          onDanmaku,
          subText: '弹幕',
        ),
        _action('detail', Icons.info_outline, '剧集详情', onDetail, subText: '详情'),
        _action('settings', Icons.tune, '播放设置', onSettings, subText: '设置'),
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
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 280,
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
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    key: const ValueKey('feed-anchor-info'),
                                    onTap: onOpenAnchorDetail,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: AppColors.hongguoRed.withValues(alpha: 0.2),
                                          child: Text(
                                            effectiveAnchor.substring(0, 1),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '@$effectiveAnchor',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (onToggleFollowAnchor != null) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      key: const ValueKey('feed-anchor-follow-btn'),
                                      onTap: onToggleFollowAnchor,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isAnchorFollowed
                                              ? const Color(0x33FFFFFF)
                                              : AppColors.hongguoRed,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isAnchorFollowed ? Icons.check : Icons.add,
                                              size: 13,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              isAnchorFollowed ? '已关注' : '关注',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              title,
                              key: const ValueKey('feed-title'),
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
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
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: actions,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: AppColors.hongguoRed,
                      activeTrackColor: AppColors.hongguoRed,
                      inactiveTrackColor: Colors.white24,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      trackHeight: 2,
                      trackShape: const RectangularSliderTrackShape(),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      key: const ValueKey('feed-seek-slider'),
                      value: progress,
                      onChanged: enabled ? onSeek : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
