import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/download/download_collections.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/settings/storage_page.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/drama/drama_cover_view.dart';
import 'package:THLRedLook/views/downloads/download_job_card.dart';

/// 按短剧剧集分类聚合的下载合集卡片
/// 支持封面海报展示、进度百分比、状态徽章、展开分集内嵌面板与专属批量操作
class DownloadCollectionCard extends StatelessWidget {
  const DownloadCollectionCard({
    super.key,
    required this.collection,
    required this.selectedCount,
    required this.expanded,
    required this.selecting,
    required this.busy,
    required this.filter,
    required this.updaterBusy,
    required this.onToggleExpand,
    required this.onSelect,
    required this.onCommand,
    this.repository,
    this.selectedJobIds,
    this.onPlayJob,
    this.onSelectJob,
    this.onJobCommand,
    this.onPlayFirst,
  });

  final DownloadCollection collection;
  final int selectedCount;
  final bool expanded;
  final bool selecting;
  final bool busy;
  final String filter;
  final bool updaterBusy;
  final VoidCallback onToggleExpand;
  final VoidCallback onSelect;
  final ValueChanged<String> onCommand;

  final AppRepository? repository;
  final Set<String>? selectedJobIds;
  final void Function(DownloadJob job)? onPlayJob;
  final void Function(DownloadJob job)? onSelectJob;
  final void Function(String command, DownloadJob job)? onJobCommand;
  final VoidCallback? onPlayFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final jobs = collection.jobs;
    final total = jobs.length;
    final completed = collection.completed;
    final isAllDone = total > 0 && completed == total;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: expanded
              ? AppColors.hongguoRed.withValues(alpha: 0.35)
              : (isDark
                    ? AppColors.white.withValues(alpha: 0.08)
                    : AppColors.black.withValues(alpha: 0.06)),
          width: expanded ? 1.2 : 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 卡片主体头部（短剧聚合信息）
          InkWell(
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧封面与多选勾选
                  _buildCover(context),
                  const SizedBox(width: 12),
                  // 中间信息区
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 剧名
                        Text(
                          collection.drama.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 5),
                        // 标签与状态小条
                        _buildMetaTags(context),
                        const SizedBox(height: 8),
                        // 进度条与容量文本
                        _buildProgressBar(context, isAllDone),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 右侧操作与菜单
                  _buildTrailing(context),
                ],
              ),
            ),
          ),

          // 2. 展开后的分集收纳容器
          if (expanded && onPlayJob != null) ...[
            const Divider(height: 1, thickness: 0.8),
            Container(
              color: isDark
                  ? AppColors.blackWithAlpha(0.25)
                  : AppColors.greyLight.withValues(alpha: 0.6),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 分集容器顶部快捷小栏
                  _buildEpisodesHeader(context),
                  const SizedBox(height: 6),
                  // 分集列表项
                  for (final job in jobs)
                    DownloadJobCard(
                      job: job,
                      selected: selectedJobIds?.contains(job.id) ?? false,
                      selecting: selecting,
                      busy: busy,
                      onSelect: () => onSelectJob?.call(job),
                      onPlay: () => onPlayJob?.call(job),
                      onCommand: (cmd) => onJobCommand?.call(cmd, job),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 54,
            height: 72,
            child: repository != null
                ? DramaCover(
                    drama: collection.drama,
                    repository: repository!,
                    radius: 8,
                    showEpisodeCount: false,
                  )
                : Container(
                    color: AppColors.hongguoRed.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.movie_outlined,
                      color: AppColors.hongguoRed,
                      size: 28,
                    ),
                  ),
          ),
        ),
        if (selecting)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.blackWithAlpha(0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Checkbox(
                  tristate: true,
                  value: selectedCount == 0
                      ? false
                      : selectedCount == collection.jobs.length
                      ? true
                      : null,
                  onChanged: busy ? null : (_) => onSelect(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMetaTags(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sourceName = SourceSite.byId(collection.drama.source).name;
    final category = collection.drama.category;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (sourceName.isNotEmpty)
          _tag(
            sourceName,
            color: AppColors.hongguoRed,
            background: AppColors.hongguoRed.withValues(alpha: isDark ? 0.2 : 0.1),
          ),
        if (category.isNotEmpty)
          _tag(
            category,
            color: theme.textTheme.bodySmall?.color ?? AppColors.grey,
            background: isDark
                ? AppColors.white.withValues(alpha: 0.08)
                : AppColors.black.withValues(alpha: 0.05),
          ),
        if (collection.active > 0)
          _tag(
            '${collection.active} 项下载中',
            color: Colors.orange,
            background: Colors.orange.withValues(alpha: isDark ? 0.2 : 0.1),
          ),
        if (collection.failed > 0)
          _tag(
            '${collection.failed} 项失败',
            color: Colors.redAccent,
            background: Colors.redAccent.withValues(alpha: isDark ? 0.2 : 0.1),
          ),
      ],
    );
  }

  Widget _tag(String text, {required Color color, required Color background}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, bool isAllDone) {
    final theme = Theme.of(context);
    final ratio = collection.jobs.isEmpty
        ? 0.0
        : (collection.completed / collection.jobs.length).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: theme.brightness == Brightness.dark
                ? AppColors.white.withValues(alpha: 0.12)
                : AppColors.black.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(
              isAllDone ? Colors.green : AppColors.hongguoRed,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${collection.completed}/${collection.jobs.length} 集已下载',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: isAllDone ? Colors.green : null,
              ),
            ),
            Text(
              storageSize(collection.bytes),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrailing(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 离线播放快捷入口
            if (collection.completed > 0 && onPlayFirst != null)
              IconButton(
                tooltip: '播放已下载分集',
                icon: const Icon(
                  Icons.play_circle_fill_rounded,
                  color: AppColors.hongguoRed,
                  size: 26,
                ),
                onPressed: busy ? null : onPlayFirst,
              ),
            // 展开折叠图标
            IconButton(
              tooltip: expanded ? '收起分集' : '展开分集',
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.grey,
              ),
              onPressed: onToggleExpand,
            ),
            // 合集专属菜单
            PopupMenuButton<String>(
              tooltip: '${collection.drama.title} · 合集操作',
              enabled: !busy,
              onSelected: onCommand,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'update',
                  enabled: !updaterBusy,
                  child: const Text('更新本剧 · 补充新增与缺失'),
                ),
                const PopupMenuItem(value: 'select', child: Text('选择本剧所有分集')),
                if (collection.completed > 0)
                  const PopupMenuItem(value: 'export', child: Text('导出本剧已下载视频')),
                const PopupMenuItem(value: 'pause', child: Text('暂停本合集')),
                const PopupMenuItem(value: 'resume', child: Text('继续 / 重试本合集')),
                const PopupMenuItem(value: 'archive', child: Text('清理已完成任务，保留视频')),
                if (filter == 'archived')
                  const PopupMenuItem(value: 'restore', child: Text('恢复到任务列表')),
                const PopupMenuItem(value: 'remove', child: Text('取消任务并删除视频')),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEpisodesHeader(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = selectedCount == collection.jobs.length && selectedCount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '分集详情 · 共 ${collection.jobs.length} 集',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.grey,
            ),
          ),
          if (selecting)
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: busy ? null : onSelect,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  allSelected ? '取消全选本剧' : '全选本剧 ($selectedCount/${collection.jobs.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.hongguoRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
