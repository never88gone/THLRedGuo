import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: '搜索剧名、站源或分类',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Text(
            '$collectionsCount 部 · $totalEpisodesCount 集'
            '${isArchivedFilter ? ' · 已清理任务，视频仍保留' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (isProgressBusy) const LinearProgressIndicator(minHeight: 2),
        if (isProgressBusy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    progressText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
            child: Text(errorMessage!),
          ),
      ],
    );
  }
}
