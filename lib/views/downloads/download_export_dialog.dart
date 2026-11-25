import 'package:flutter/material.dart';

import 'package:THLRedLook/core/download/download_exporter.dart';
import 'package:THLRedLook/models/download/download_job.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 视频解密导出进度对话框
class DownloadExportDialog extends StatefulWidget {
  const DownloadExportDialog({
    super.key,
    required this.exporter,
    required this.jobs,
    required this.targetDirectory,
  });

  final DownloadExporter exporter;
  final List<DownloadJob> jobs;
  final String targetDirectory;

  static Future<DownloadExportResult?> show({
    required BuildContext context,
    required DownloadExporter exporter,
    required List<DownloadJob> jobs,
    required String targetDirectory,
  }) {
    return showDialog<DownloadExportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DownloadExportDialog(
        exporter: exporter,
        jobs: jobs,
        targetDirectory: targetDirectory,
      ),
    );
  }

  @override
  State<DownloadExportDialog> createState() => _DownloadExportDialogState();
}

class _DownloadExportDialogState extends State<DownloadExportDialog> {
  int _current = 0;
  int _total = 0;
  double _fraction = 0.0;
  String _status = '正在准备导出...';
  String? _error;
  bool _finished = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _total = widget.jobs.where((j) => j.completed).length;
    _startExport();
  }

  void _startExport() {
    widget.exporter
        .exportJobs(
          jobs: widget.jobs,
          targetDirectory: widget.targetDirectory,
        )
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() {
              _current = progress.current;
              _total = progress.total;
              _fraction = progress.fraction;
              _status = progress.status;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _error = error.toString().replaceFirst(RegExp(r'^AppFailure:\s*'), '');
              _status = '导出失败';
              _finished = true;
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() {
              _fraction = 1.0;
              _status = '全部导出完成！普通播放器可直接播放';
              _finished = true;
            });
          },
          cancelOnError: true,
        );
  }

  void _onCancel() {
    setState(() => _cancelling = true);
    widget.exporter.cancel();
    Navigator.of(context).pop(
      DownloadExportResult(
        successCount: _current > 0 ? _current - 1 : 0,
        failureCount: 0,
        outputDirectory: widget.targetDirectory,
        cancelled: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_fraction * 100).clamp(0, 100).toStringAsFixed(1);
    final isDoneSuccess = _finished && _error == null;

    return AlertDialog(
      key: const ValueKey('download-export-dialog'),
      title: Row(
        children: [
          Icon(
            isDoneSuccess
                ? Icons.check_circle_rounded
                : _error != null
                ? Icons.error_outline_rounded
                : Icons.output_rounded,
            color: isDoneSuccess
                ? AppColors.success
                : _error != null
                ? AppColors.error
                : AppColors.hongguoRed,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            isDoneSuccess
                ? '视频导出完成'
                : _error != null
                ? '导出遇到问题'
                : '正在解密并导出视频',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_finished) ...[
              LinearProgressIndicator(
                value: _fraction.clamp(0.0, 1.0),
                backgroundColor: AppColors.darkSurfaceHigh,
                valueColor: const AlwaysStoppedAnimation(AppColors.hongguoRed),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_current / $_total 集',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Text(
              _error ?? _status,
              style: TextStyle(
                fontSize: 13,
                color: _error != null
                    ? AppColors.error
                    : AppColors.textPrimaryDark,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_open_rounded,
                    size: 16,
                    color: AppColors.hongguoRed,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.targetDirectory,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_finished)
          TextButton(
            key: const ValueKey('download-export-cancel-btn'),
            onPressed: _cancelling ? null : _onCancel,
            child: Text(
              _cancelling ? '正在取消...' : '取消导出',
              style: const TextStyle(color: AppColors.error),
            ),
          )
        else
          FilledButton(
            key: const ValueKey('download-export-finish-btn'),
            onPressed: () {
              Navigator.of(context).pop(
                DownloadExportResult(
                  successCount: _error == null ? _total : _current,
                  failureCount: _error != null ? 1 : 0,
                  outputDirectory: widget.targetDirectory,
                  errorMessage: _error,
                ),
              );
            },
            child: const Text('完成'),
          ),
      ],
    );
  }
}
