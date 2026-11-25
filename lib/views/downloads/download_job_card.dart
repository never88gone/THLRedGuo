import 'package:flutter/material.dart';

import 'package:THLRedLook/models/download/download_job.dart';
import 'package:THLRedLook/pages/settings/storage_page.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/views/remote/remote_widgets.dart';

class DownloadJobCard extends StatelessWidget {
  const DownloadJobCard({
    super.key,
    required this.job,
    required this.selected,
    required this.selecting,
    required this.busy,
    required this.onSelect,
    required this.onPlay,
    required this.onCommand,
  });

  final DownloadJob job;
  final bool selected;
  final bool selecting;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final ValueChanged<String> onCommand;

  void _showTvJobMenu(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${job.drama.title} · 第 ${job.episode.number} 集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (job.resumable)
              FilledButton(
                autofocus: true,
                onPressed: () {
                  Navigator.pop(context);
                  onCommand('resume');
                },
                child: const Text('继续下载'),
              ),
            if (job.active)
              FilledButton(
                autofocus: true,
                onPressed: () {
                  Navigator.pop(context);
                  onCommand('pause');
                },
                child: const Text('暂停下载'),
              ),
            if (job.completed) ...[
              FilledButton(
                autofocus: true,
                onPressed: () {
                  Navigator.pop(context);
                  onPlay();
                },
                child: const Text('本地播放'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onCommand('export');
                },
                child: const Text('导出视频'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onCommand('remove');
              },
              child: Text(job.completed ? '删除视频' : '取消下载'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tv = AppLayout.isTelevision(context);
    final card = Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: selecting
                ? Checkbox(
                    value: selected,
                    onChanged: busy ? null : (_) => onSelect(),
                  )
                : Icon(
                    job.completed
                        ? Icons.offline_pin_outlined
                        : job.state == 'failed'
                        ? Icons.error_outline
                        : Icons.downloading_rounded,
                  ),
            title: Text(
              '第 ${job.episode.number} 集${job.episode.vip ? ' · VIP' : ''}',
            ),
            subtitle: Text(
              '${job.archived ? '已保留视频' : job.stateLabel} · ${storageSize(job.bytes)}'
              '${job.actualQuality > 0 ? ' · ${job.actualQuality}P' : ''}${job.error.isNotEmpty ? '\n${job.error}' : ''}',
            ),
            onTap: busy
                ? null
                : selecting
                ? onSelect
                : job.completed
                ? onPlay
                : null,
            trailing: selecting
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (job.completed)
                        IconButton(
                          key: ValueKey('local-play-${job.id}'),
                          tooltip: '本地播放',
                          icon: const Icon(Icons.play_circle_outline_rounded),
                          onPressed: busy ? null : onPlay,
                        ),
                      if (job.active)
                        IconButton(
                          key: ValueKey('pause-${job.id}'),
                          tooltip: '暂停',
                          icon: const Icon(Icons.pause_circle_outline_rounded),
                          onPressed: busy ? null : () => onCommand('pause'),
                        ),
                      if (job.resumable)
                        IconButton(
                          key: ValueKey('resume-${job.id}'),
                          tooltip: '继续 / 重试',
                          icon: const Icon(Icons.play_circle_outline_rounded),
                          onPressed: busy ? null : () => onCommand('resume'),
                        ),
                      IconButton(
                        key: ValueKey('remove-${job.id}'),
                        tooltip: job.completed ? '删除视频' : '取消下载',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: busy ? null : () => onCommand('remove'),
                      ),
                      PopupMenuButton<String>(
                        enabled: !busy,
                        tooltip: '分集操作',
                        onSelected: (value) {
                          if (value == 'play') {
                            onPlay();
                          } else {
                            onCommand(value);
                          }
                        },
                        itemBuilder: (_) => [
                          if (job.completed) ...[
                            const PopupMenuItem(
                              value: 'play',
                              child: Text('本地播放'),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Text('导出视频'),
                            ),
                          ],
                          if (job.active)
                            const PopupMenuItem(
                              value: 'pause',
                              child: Text('暂停'),
                            ),
                          if (job.resumable)
                            const PopupMenuItem(
                              value: 'resume',
                              child: Text('继续 / 重试'),
                            ),
                          if (job.completed)
                            PopupMenuItem(
                              value: job.archived ? 'restore' : 'archive',
                              child: Text(job.archived ? '恢复任务' : '清理任务，保留视频'),
                            ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(job.completed ? '删除视频' : '取消下载'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          if (!job.completed)
            LinearProgressIndicator(
              value: job.progress > 0 || !job.active ? job.progress : null,
              minHeight: 2,
            ),
        ],
      ),
    );

    if (tv) {
      return Padding(
        padding: const EdgeInsets.only(left: 12),
        child: RemoteTarget(
          key: ValueKey('download-task-${job.id}'),
          onPressed: () => _showTvJobMenu(context),
          child: card,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: KeyedSubtree(
        key: ValueKey('download-task-${job.id}'),
        child: card,
      ),
    );
  }
}
