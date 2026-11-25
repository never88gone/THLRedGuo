import 'package:flutter/material.dart';

import 'package:THLRedLook/core/download/download_collections.dart';
import 'package:THLRedLook/pages/settings/storage_page.dart';

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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: selecting
            ? Checkbox(
                tristate: true,
                value: selectedCount == 0
                    ? false
                    : selectedCount == collection.jobs.length
                    ? true
                    : null,
                onChanged: busy ? null : (_) => onSelect(),
              )
            : Icon(expanded ? Icons.folder_open_rounded : Icons.folder_rounded),
        title: Text(
          collection.drama.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${collection.completed}/${collection.jobs.length} 集已下载 · ${storageSize(collection.bytes)}'
          '${collection.active > 0 ? ' · ${collection.active} 项进行中' : ''}${collection.failed > 0 ? ' · ${collection.failed} 项失败' : ''}',
        ),
        onTap: onToggleExpand,
        trailing: PopupMenuButton<String>(
          tooltip: '${collection.drama.title} · 合集操作',
          enabled: !busy,
          onSelected: onCommand,
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'update',
              enabled: !updaterBusy,
              child: const Text('更新本剧 · 补充新增与缺失'),
            ),
            const PopupMenuItem(value: 'select', child: Text('选择本合集')),
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
      ),
    );
  }
}
