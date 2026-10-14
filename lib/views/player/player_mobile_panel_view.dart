import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../core_bridge.dart';
import '../../download_picker.dart';
import '../../follow_state.dart';
import '../../hongguo_series.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../../player_menu.dart';
import '../../widgets.dart';

/// 移动端半屏沉浸模式下的底部信息与交互面板（选集、简介、下载）
class PlayerMobilePanelView extends StatefulWidget {
  const PlayerMobilePanelView({
    super.key,
    required this.detail,
    required this.currentIndex,
    required this.store,
    required this.repository,
    required this.onSelectEpisode,
    this.onSubmitDownload,
    this.seriesEntries = const [],
    this.onSeasonSelected,
  });

  final DramaDetail detail;
  final int currentIndex;
  final LocalStore store;
  final AppRepository repository;
  final ValueChanged<int> onSelectEpisode;
  final Future<void> Function(DownloadSelection selection)? onSubmitDownload;
  final List<HongguoSeriesEntry> seriesEntries;
  final ValueChanged<Drama>? onSeasonSelected;

  @override
  State<PlayerMobilePanelView> createState() => _PlayerMobilePanelViewState();
}

class _PlayerMobilePanelViewState extends State<PlayerMobilePanelView> {
  int _currentTab = 0;

  Widget _tabButton(int index, String label) {
    final selected = _currentTab == index;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _currentTab = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? (theme.brightness == Brightness.dark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight)
                    : colorScheme.onSurfaceVariant,
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 22 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? AppColors.hongguoRed : AppColors.transparent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _synopsisTab() {
    final drama = widget.detail.drama;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final meta = [
      SourceSite.byId(drama.source).name,
      if (drama.episodes > 0) '共 ${drama.episodes} 集',
      if (drama.releaseStatus.isNotEmpty && drama.releaseStatus != 'unknown')
        drama.releaseLabel,
      if (drama.category.isNotEmpty) drama.category,
    ];
    final body = drama.description.trim().isEmpty ? '暂无简介' : drama.description;

    return ColoredBox(
      color: colors.surface,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 82,
                height: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: DramaCover(drama: drama, repository: widget.repository),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      drama.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        meta.join(' · '),
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                    if (drama.onlineDate.isNotEmpty || drama.heat.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (drama.onlineDate.isNotEmpty) '${drama.onlineDate} 上线',
                          if (drama.heat.isNotEmpty) '热度 ${drama.heat}',
                        ].join(' · '),
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _mobileFollowControl(drama),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(height: 1.5, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _mobileFollowControl(Drama drama) {
    final state = widget.store.following(drama.id);
    return PopupMenuButton<String>(
      key: const ValueKey('player-follow-status'),
      tooltip: '追剧与观看状态',
      onSelected: (value) async {
        if (value == 'remove') {
          await saveUserChange(
            context,
            () => widget.store.toggleFavorite(drama),
          );
        } else {
          final status = FollowStatus.values.firstWhere(
            (status) => status.name == value,
          );
          await saveUserChange(
            context,
            () => widget.store.setFollowStatus(drama, status),
          );
        }
        if (mounted) setState(() {});
      },
      itemBuilder: (_) => [
        for (final status in FollowStatus.values)
          CheckedPopupMenuItem(
            value: status.name,
            checked: state?.status == status,
            child: Text(status.label),
          ),
        if (state != null)
          const PopupMenuItem(value: 'remove', child: Text('取消追剧')),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: state == null
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state == null
                  ? Icons.bookmark_add_outlined
                  : Icons.bookmark_rounded,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(state?.label ?? '加入追剧'),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _downloadTab() {
    final colors = Theme.of(context).colorScheme;
    if (!widget.repository.supportsDownloads || !widget.store.canDownload) {
      return ColoredBox(
        color: colors.surface,
        child: const Center(
          child: Text('当前环境或权限暂未开放本地下载'),
        ),
      );
    }
    return DownloadPicker(
      detail: widget.detail,
      preferences: widget.store.downloadPreferences,
      embedded: true,
      onSubmit: widget.onSubmitDownload,
    );
  }

  Widget _buildSeriesBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentId = widget.detail.drama.id;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceHigh : AppColors.lightSurfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
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
                  '共 ${widget.seriesEntries.length} 季',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.hongguoRed,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '点击快速切季',
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in widget.seriesEntries) ...[
                  Builder(
                    builder: (_) {
                      final isCurrent = entry.drama.id == currentId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: isCurrent
                              ? null
                              : () => widget.onSeasonSelected?.call(entry.drama),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppColors.hongguoRed
                                  : (isDark
                                      ? AppColors.darkSurfaceHighest
                                      : AppColors.lightSurface),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrent
                                    ? AppColors.hongguoRed
                                    : (isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrent) ...[
                                  const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 13,
                                    color: AppColors.white,
                                  ),
                                  const SizedBox(width: 3),
                                ],
                                Text(
                                  entry.label,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isCurrent
                                        ? AppColors.white
                                        : (isDark
                                            ? AppColors.textPrimaryDark
                                            : AppColors.textPrimaryLight),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
              child: SizedBox(
                height: 42,
                child: Row(
                  children: [
                    _tabButton(0, '选集'),
                    _tabButton(1, '简介'),
                    _tabButton(2, '下载'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _currentTab == 0
                      ? ColoredBox(
                          color: colors.surface,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.seriesEntries.isNotEmpty)
                                _buildSeriesBar(),
                              Expanded(
                                child: PlayerEpisodeGrid(
                                  episodes: widget.detail.episodes,
                                  currentIndex: widget.currentIndex,
                                  compact: true,
                                  title: '剧集',
                                  onSelected: widget.onSelectEpisode,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _currentTab == 1
                      ? _synopsisTab()
                      : _downloadTab(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
