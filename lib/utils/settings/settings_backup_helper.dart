import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/build/app_build.dart';
import 'package:THLRedLook/core/store/local_store.dart';

class SettingsBackupHelper {
  const SettingsBackupHelper();

  static Future<Uri?> exportBackup(LocalStore store) async {
    final content = await store.exportBackup();
    final fileName =
        '$appSlug-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    return FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: 'application/json',
    );
  }

  static Future<bool> restoreBackup(
    BuildContext context,
    LocalStore store,
  ) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null || !context.mounted) return false;
    final size = await file.length();
    if (size == null || size > 8 * 1024 * 1024) {
      throw const FormatException('备份文件过大或无法读取');
    }
    final content = utf8.decode(await file.readAsBytes());
    final data = store.validateBackup(content);
    if (!context.mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复配置备份？'),
        content: Text(
          '包含 ${(data['profiles'] as List).length} 个用户配置。将替换本机的用户档案、追剧收藏与偏好设置。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即恢复'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await store.importBackup(content);
      if (!context.mounted) return false;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return true;
    }
    return false;
  }
}
