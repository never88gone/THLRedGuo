import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/build/app_build.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/models/catalog/models.dart';

/// 首页顶部导航栏组件
class HomeAppBarView extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBarView({
    super.key,
    required this.selectionMode,
    required this.selectedEmpty,
    required this.tab,
    required this.sourceGroups,
    required this.group,
    required this.showRecommendations,
    required this.searchVisible,
    required this.television,
    required this.canDownload,
    required this.supportsDownloads,
    required this.supportsSourceManagement,
    required this.sourcesEmpty,
    required this.loading,
    required this.isUpdaterBusy,
    required this.catalogSortLabel,
    required this.isSortedOrFiltered,
    required this.screenWidth,
    required this.onClearSelection,
    required this.onCancelSelection,
    required this.onChangeGroup,
    required this.onChooseCatalogView,
    required this.onOpenRankings,
    required this.onStartSelection,
    required this.onToggleSearch,
    required this.onRefreshCatalog,
    required this.onMoreAction,
    this.onOpenSourceSwitcher,
  });

  final bool selectionMode;
  final bool selectedEmpty;
  final int tab;
  final List<SourceGroup> sourceGroups;
  final SourceGroup group;
  final bool showRecommendations;
  final bool searchVisible;
  final bool television;
  final bool canDownload;
  final bool supportsDownloads;
  final bool supportsSourceManagement;
  final bool sourcesEmpty;
  final bool loading;
  final bool isUpdaterBusy;
  final String catalogSortLabel;
  final bool isSortedOrFiltered;
  final double screenWidth;

  final VoidCallback onClearSelection;
  final VoidCallback onCancelSelection;
  final ValueChanged<SourceGroup> onChangeGroup;
  final VoidCallback onChooseCatalogView;
  final VoidCallback onOpenRankings;
  final VoidCallback onStartSelection;
  final VoidCallback onToggleSearch;
  final VoidCallback onRefreshCatalog;
  final ValueChanged<String> onMoreAction;
  final VoidCallback? onOpenSourceSwitcher;

  @override
  Size get preferredSize => Size.fromHeight(television ? 64.0 : kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: television ? 64 : null,
      titleSpacing: 12,
      title: selectionMode
          ? const Text('选择短剧', maxLines: 1, overflow: TextOverflow.ellipsis)
          : tab == 0
          ? InkWell(
              key: const ValueKey('source-switch'),
              borderRadius: BorderRadius.circular(12),
              onTap: onOpenSourceSwitcher,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: (screenWidth - 240).clamp(100.0, 200.0),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkSurfaceHighest70
                      : AppColors.greyLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.movie_filter_rounded, size: 18, color: AppColors.hongguoRed),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            )
          : const Text(appName),
      actions: [
        if (selectionMode) ...[
          TextButton(
            key: const ValueKey('clear-catalog-selection'),
            onPressed: selectedEmpty ? null : onClearSelection,
            child: const Text('清空'),
          ),
          TextButton(
            key: const ValueKey('cancel-catalog-selection'),
            onPressed: onCancelSelection,
            child: const Text('取消'),
          ),
        ] else ...[
          if (tab == 0) ...[
            if (!showRecommendations && screenWidth >= 850)
              IconButton(
                tooltip: '排序与筛选 · $catalogSortLabel',
                onPressed: onChooseCatalogView,
                color: isSortedOrFiltered ? Theme.of(context).colorScheme.primary : null,
                icon: const Icon(Icons.sort_rounded),
              ),
            if (sourceGroups.length > 1 && screenWidth >= 900)
              IconButton(
                key: const ValueKey('open-source-switcher'),
                tooltip: '切换数据源',
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: onOpenSourceSwitcher,
              ),
            IconButton(
              key: const ValueKey('open-rankings'),
              tooltip: '榜单',
              onPressed: sourcesEmpty ? null : onOpenRankings,
              icon: const Icon(Icons.leaderboard_outlined),
            ),
            if (!showRecommendations && canDownload && supportsDownloads && screenWidth >= 850)
              IconButton(
                key: const ValueKey('select-catalog-dramas'),
                tooltip: '多选下载',
                onPressed: onStartSelection,
                icon: const Icon(Icons.checklist_rounded),
              ),
            IconButton(
              key: const ValueKey('toggle-search'),
              tooltip: searchVisible ? '收起搜索' : '搜索',
              icon: Icon(
                searchVisible ? Icons.search_off_rounded : Icons.search_rounded,
              ),
              onPressed: onToggleSearch,
            ),
          ],
          IconButton(
            key: const ValueKey('home-appbar-settings-button'),
            tooltip: '设置',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => onMoreAction('settings'),
          ),
        ],
      ],
    );
  }
}
