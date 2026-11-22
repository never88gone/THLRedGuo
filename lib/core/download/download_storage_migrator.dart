import 'dart:io';

import 'package:path/path.dart' as p;

/// 负责将本地离线短剧目录与文件安全迁移至新路径的工具类
abstract final class DownloadStorageMigrator {
  static Future<void> moveDirectoryContents(
    String sourceDir,
    String targetDir,
  ) async {
    final newDir = Directory(targetDir);
    await newDir.create(recursive: true);

    final currentDir = Directory(sourceDir);
    if (await currentDir.exists()) {
      await for (final entity in currentDir.list(recursive: false)) {
        final dest = p.join(targetDir, p.basename(entity.path));
        if (entity is File) {
          await entity.copy(dest);
          await entity.delete();
        } else if (entity is Directory) {
          final targetSubDir = Directory(dest);
          await targetSubDir.create(recursive: true);
          await for (final subEntity in entity.list(recursive: false)) {
            if (subEntity is File) {
              await subEntity.copy(
                p.join(targetSubDir.path, p.basename(subEntity.path)),
              );
              await subEntity.delete();
            }
          }
          await entity.delete(recursive: true);
        }
      }
    }
  }
}
