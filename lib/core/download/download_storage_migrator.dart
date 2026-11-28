import 'dart:io';

import 'package:path/path.dart' as p;

/// 负责将本地离线短剧目录与文件安全迁移至新路径的工具类
abstract final class DownloadStorageMigrator {
  static Future<void> moveDirectoryContents(
    String sourceDir,
    String targetDir,
  ) async {
    final currentDir = Directory(sourceDir);
    final newDir = Directory(targetDir);
    await newDir.create(recursive: true);
    if (!await currentDir.exists()) return;

    final srcReal = await currentDir.resolveSymbolicLinks();
    final dstReal = await newDir.resolveSymbolicLinks();
    if (p.equals(srcReal, dstReal)) return;
    if (p.isWithin(srcReal, dstReal)) {
      throw ArgumentError('不能将下载目录迁移到当前目录的子目录中');
    }

    await _copyRecursive(currentDir, newDir);
    await for (final entity in currentDir.list(
      recursive: false,
      followLinks: false,
    )) {
      await entity.delete(recursive: true);
    }
  }

  static Future<void> _copyRecursive(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: false,
      followLinks: false,
    )) {
      final destPath = p.join(target.path, p.basename(entity.path));
      if (entity is File) {
        final expectedLength = await entity.length();
        final copied = await entity.copy(destPath);
        if (await copied.length() != expectedLength) {
          throw FileSystemException('迁移校验失败，文件大小不一致', destPath);
        }
      } else if (entity is Directory) {
        await _copyRecursive(entity, Directory(destPath));
      }
    }
  }
}
