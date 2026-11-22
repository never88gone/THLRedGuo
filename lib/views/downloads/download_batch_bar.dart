import 'package:flutter/material.dart';

class DownloadBatchBar extends StatelessWidget {
  const DownloadBatchBar({
    super.key,
    required this.busy,
    required this.hasSelected,
    required this.retryCommand,
    required this.onStopBatch,
    required this.onBatchCommand,
  });

  final bool busy;
  final bool hasSelected;
  final String? retryCommand;
  final VoidCallback onStopBatch;
  final ValueChanged<String> onBatchCommand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (busy)
                TextButton(
                  onPressed: onStopBatch,
                  child: const Text('停止批量操作'),
                )
              else ...[
                for (final entry in const {
                  'pause': '暂停',
                  'resume': '继续 / 重试',
                  'archive': '保留视频',
                  'remove': '删除',
                }.entries)
                  TextButton(
                    onPressed: !hasSelected
                        ? null
                        : () => onBatchCommand(entry.key),
                    child: Text(entry.value),
                  ),
                if (retryCommand != null)
                  FilledButton(
                    onPressed: () => onBatchCommand(retryCommand!),
                    child: const Text('重试失败项'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
