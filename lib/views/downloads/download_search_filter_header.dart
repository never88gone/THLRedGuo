import 'package:flutter/material.dart';

import 'package:THLRedLook/pages/settings/storage_page.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class DownloadSearchFilterHeader extends StatelessWidget {
  const DownloadSearchFilterHeader({
    super.key,
    required this.currentFilter,
    required this.onFilterSelected,
    required this.searchController,
    required this.onSearchChanged,
    required this.collectionsCount,
    required this.totalEpisodesCount,
    required this.isArchivedFilter,
    required this.isProgressBusy,
    required this.progressText,
    required this.canCancelUpdater,
    this.onCancelUpdater,
    this.errorMessage,
    this.totalBytes = 0,
  });

  final String currentFilter;
  final ValueChanged<String> onFilterSelected;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final int collectionsCount;
  final int totalEpisodesCount;
  final bool isArchivedFilter;
  final bool isProgressBusy;
  final String progressText;
  final bool canCancelUpdater;
  final VoidCallback? onCancelUpdater;
  final String? errorMessage;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 筛选标签胶囊
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SingleChildScrollView(
            key: const ValueKey('download-filters'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (k, label) in [
                  ('all', '全部'),
                  ('downloading', '下载中'),
                  ('completed', '已下载'),
                  ('archived', '已保留视频'),
                ]) ...[
                  ChoiceChip(
                    key: ValueKey('download-filter-$k'),
                    label: Text(label),
                    selected: currentFilter == k,
                    selectedColor: AppColors.hongguoRed.withValues(alpha: 0.18),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: currentFilter == k ? FontWeight.w700 : FontWeight.w500,
                      color: currentFilter == k ? AppColors.hongguoRed : null,
                    ),
                    onSelected: (selected) {
                      if (selected) onFilterSelected(k);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),

        // 2. 搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: '搜索剧名、站源或分类',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: isDark
                    ? AppColors.white.withValues(alpha: 0.06)
                    : AppColors.black.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
              ),
            ),
          ),
        ),

        // 3. 统计小字与空间占用
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$collectionsCount 部短剧 · $totalEpisodesCount 集'
                '${isArchivedFilter ? ' · 已清理任务，视频仍保留' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.grey,
                ),
              ),
              if (totalBytes > 0)
                Text(
                  '占用 ${storageSize(totalBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.hongguoRed,
                  ),
                ),
            ],
          ),
        ),

        if (isProgressBusy) const LinearProgressIndicator(minHeight: 2),
        if (isProgressBusy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    progressText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (canCancelUpdater && onCancelUpdater != null)
                  TextButton(
                    onPressed: onCancelUpdater,
                    child: const Text('停止'),
                  ),
              ],
            ),
          ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(errorMessage!, style: const TextStyle(color: Colors.redAccent)),
          ),
      ],
    );
  }
}
