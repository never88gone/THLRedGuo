import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/player/player_episode_grid.dart';

/// 桌面端与宽屏模式下的右侧选集分栏组件
class PlayerDesktopPanelView extends StatelessWidget {
  const PlayerDesktopPanelView({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onSelectEpisode,
    this.compact = false,
    this.seriesEntries = const [],
    this.currentDramaId,
    this.onSeasonSelected,
    this.onFullscreen,
  });

  final List<Episode> episodes;
  final int currentIndex;
  final ValueChanged<int> onSelectEpisode;
  final bool compact;
  final List<HongguoSeriesEntry> seriesEntries;
  final String? currentDramaId;
  final ValueChanged<Drama>? onSeasonSelected;
  final VoidCallback? onFullscreen;

  Widget _buildSeriesBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_rounded, size: 14, color: AppColors.hongguoRed),
              const SizedBox(width: 4),
              Text(
                '系列多季',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accentTrack35,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '共 ${seriesEntries.length} 季',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.hongguoRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in seriesEntries) ...[
                  Builder(
                    builder: (_) {
                      final isCurrent = entry.drama.id == currentDramaId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          key: ValueKey('player-season-${entry.drama.id}'),
                          onTap: isCurrent || !entry.playable ? null : () => onSeasonSelected?.call(entry.drama),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppColors.hongguoRed
                                  : (isDark ? AppColors.darkSurfaceHighest : AppColors.lightSurfaceHigh),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrent
                                    ? AppColors.hongguoRed
                                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrent) ...[
                                  const Icon(Icons.play_arrow_rounded, size: 12, color: AppColors.white),
                                  const SizedBox(width: 2),
                                ],
                                Text(
                                  entry.label,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrent
                                        ? AppColors.white
                                        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(12, topPadding > 0 ? topPadding + 4 : 8, 8, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '剧集列表',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('panel-enter-fullscreen'),
            onPressed: onFullscreen,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.hongguoRed,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.fullscreen_rounded, size: 18),
            label: const Text('全屏观看', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onFullscreen != null) _buildPanelHeader(context),
          if (seriesEntries.isNotEmpty) _buildSeriesBar(context),
          Expanded(
            child: PlayerEpisodeGrid(
              episodes: episodes,
              currentIndex: currentIndex,
              compact: compact,
              title: compact ? '剧集' : '选集',
              onSelected: onSelectEpisode,
            ),
          ),
        ],
      ),
    );
  }
}
