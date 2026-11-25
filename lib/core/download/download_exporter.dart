import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/media/media_pipeline.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/download/download_job.dart';

/// 导出进度通知载荷
class DownloadExportProgress {
  const DownloadExportProgress({
    required this.total,
    required this.current,
    required this.job,
    required this.status,
    this.fraction = 0.0,
    this.targetPath = '',
  });

  final int total;
  final int current;
  final DownloadJob job;
  final String status;
  final double fraction;
  final String targetPath;
}

/// 导出结果汇总
class DownloadExportResult {
  const DownloadExportResult({
    required this.successCount,
    required this.failureCount,
    required this.outputDirectory,
    this.cancelled = false,
    this.errorMessage,
  });

  final int successCount;
  final int failureCount;
  final String outputDirectory;
  final bool cancelled;
  final String? errorMessage;
}

/// 负责将已下载的（含加密流的）分集视频解密、去DRM并无损封装导出到用户指定公共目录
class DownloadExporter {
  DownloadExporter({
    required this.repository,
    MediaExecutor? executor,
  }) : _executor = executor ?? FFmpegExecutor();

  final AppRepository repository;
  final MediaExecutor _executor;
  bool _cancelled = false;

  static const String _prefLastExportDir = 'last_video_export_directory';

  void cancel() {
    _cancelled = true;
    _executor.cancel();
  }

  /// 获取上次记忆的导出目录
  static Future<String?> getLastExportDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dir = prefs.getString(_prefLastExportDir);
      if (dir != null && dir.isNotEmpty && await Directory(dir).exists()) {
        return dir;
      }
    } catch (_) {}
    return null;
  }

  /// 记忆本次导出的目标目录
  static Future<void> saveLastExportDirectory(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastExportDir, path);
    } catch (_) {}
  }

  /// 唤起系统原生目录选择器
  static Future<String?> pickExportDirectory({String? initialDirectory}) async {
    final initial = initialDirectory ?? await getLastExportDirectory();
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: '选择视频导出目录',
      initialDirectory: initial,
    );
    if (selected != null && selected.isNotEmpty) {
      await saveLastExportDirectory(selected);
    }
    return selected;
  }

  /// 清洗操作系统非法文件名字符
  static String safeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
  }

  /// 执行解密并导出视频文件列表
  Stream<DownloadExportProgress> exportJobs({
    required List<DownloadJob> jobs,
    required String targetDirectory,
  }) async* {
    _cancelled = false;
    final validJobs = jobs.where((job) => job.completed).toList();
    if (validJobs.isEmpty) return;

    final targetDir = Directory(targetDirectory);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final isSingleDrama =
        validJobs.map((j) => j.drama.id).toSet().length == 1;
    final total = validJobs.length;

    for (var i = 0; i < total; i++) {
      if (_cancelled) {
        throw AppFailure('已取消视频导出');
      }

      final job = validJobs[i];
      final dramaTitle = safeFileName(
        job.drama.title.isNotEmpty ? job.drama.title : '短剧',
      );
      final epNum = job.episode.number;
      final padCount = total >= 100 || (job.drama.episodes >= 100) ? 3 : 2;
      final epLabel = '第${epNum.toString().padLeft(padCount, '0')}集';

      // 目录规划：单剧多集导出时置于独立剧名文件夹下；单集导出直出
      final destinationDir = isSingleDrama && total > 1
          ? Directory(p.join(targetDirectory, dramaTitle))
          : targetDir;

      if (!await destinationDir.exists()) {
        await destinationDir.create(recursive: true);
      }

      final fileName = isSingleDrama && total > 1
          ? '$epLabel.mp4'
          : '$dramaTitle - $epLabel.mp4';
      final outputFile = File(p.join(destinationDir.path, fileName));
      final tempOutputFile = File('${outputFile.path}.part');

      yield DownloadExportProgress(
        total: total,
        current: i + 1,
        job: job,
        status: '正在解密并导出 $dramaTitle $epLabel...',
        fraction: i / total,
        targetPath: outputFile.path,
      );

      try {
        final plan = await repository.localPlayback(job.drama, job.episode);
        if (_cancelled) throw AppFailure('已取消视频导出');
        if (plan == null || !plan.local) {
          throw AppFailure('未找到第 $epNum 集的本地视频文件');
        }

        final sourceFile = File(plan.url);
        if (!await sourceFile.exists() || await sourceFile.length() == 0) {
          throw AppFailure('第 $epNum 集本地源文件缺失或为空');
        }

        if (await tempOutputFile.exists()) {
          await tempOutputFile.delete();
        }

        if (plan.decryptionKey.isNotEmpty) {
          // 使用 FFmpeg 进行无损流解密复制 (Remux)，不重编画面，极速且原画质
          await _executor.run([
            '-decryption_key',
            plan.decryptionKey,
            '-i',
            sourceFile.path,
            '-map',
            '0:v:0',
            '-map',
            '0:a:0?',
            '-c',
            'copy',
            '-map_metadata',
            '-1',
            '-avoid_negative_ts',
            'make_zero',
            tempOutputFile.path,
          ]);
        } else {
          // 普通非加密流，直接原文件安全复制
          await sourceFile.copy(tempOutputFile.path);
        }

        if (_cancelled) {
          if (await tempOutputFile.exists()) await tempOutputFile.delete();
          throw AppFailure('已取消视频导出');
        }

        if (await tempOutputFile.exists() && await tempOutputFile.length() > 0) {
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
          await tempOutputFile.rename(outputFile.path);
        } else {
          throw AppFailure('导出生成的目标文件无效');
        }

        yield DownloadExportProgress(
          total: total,
          current: i + 1,
          job: job,
          status: '已导出 $dramaTitle $epLabel',
          fraction: (i + 1) / total,
          targetPath: outputFile.path,
        );
      } catch (e) {
        if (await tempOutputFile.exists()) {
          try {
            await tempOutputFile.delete();
          } catch (_) {}
        }
        if (_cancelled) rethrow;
        throw AppFailure('导出第 $epNum 集失败: $e');
      }
    }
  }
}
