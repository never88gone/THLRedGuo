import 'package:flutter/material.dart';

Future<Map<String, String>?> showDownloadFilterDialog({
  required BuildContext context,
  required String currentFilter,
  required String currentRelease,
}) async {
  var state = currentFilter;
  var release = currentRelease;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, change) => AlertDialog(
        title: const Text('筛选下载合集'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('任务状态'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {
                      'all': '全部任务',
                      'pending': '未完成',
                      'active': '进行中',
                      'paused': '已暂停',
                      'failed': '失败',
                      'completed': '已下载',
                      'archived': '已保留视频',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: state == entry.key,
                        onSelected: (_) => change(() => state = entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('剧集状态'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {
                      '': '全部',
                      'ongoing': '连载中',
                      'finished': '已完结',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: release == entry.key,
                        onSelected: (_) => change(() => release = entry.key),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('应用'),
          ),
        ],
      ),
    ),
  );
  if (result == true) {
    return {'filter': state, 'release': release};
  }
  return null;
}
