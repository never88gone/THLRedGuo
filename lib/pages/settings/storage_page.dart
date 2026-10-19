import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/views/settings/settings_group_view.dart';

String storageSize(int bytes) {
  if (bytes < 0) return '暂不可用';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, dynamic>? _info;
  String? _error;
  bool _busy = false;

  int _cacheBytes = 0;
  bool _isLoadingCache = false;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final info = await widget.repository.storage();
      if (mounted) {
        setState(() {
          _info = info;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
    await _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    if (!mounted) return;
    setState(() => _isLoadingCache = true);
    try {
      final size = await _calculateCacheSize();
      if (mounted) {
        setState(() {
          _cacheBytes = size;
          _isLoadingCache = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingCache = false);
      }
    }
  }

  Future<int> _calculateCacheSize() async {
    int total = 0;
    final Set<String> visitedPaths = {};

    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists() && visitedPaths.add(tempDir.path)) {
        total += await _calcDirSize(tempDir);
      }
    } catch (_) {}

    try {
      final cacheDir = await getApplicationCacheDirectory();
      if (await cacheDir.exists() && visitedPaths.add(cacheDir.path)) {
        total += await _calcDirSize(cacheDir);
      }
    } catch (_) {}

    return total;
  }

  Future<int> _calcDirSize(Directory dir) async {
    int size = 0;
    try {
      if (!dir.existsSync()) return 0;
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          try {
            size += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return size;
  }

  Future<void> _handleClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理应用缓存？'),
        content: const Text(
          '将清理临时运行数据、海报图片缓存与网络分片。已下载的离线短剧及追剧记录不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isClearingCache = true);
    final freedBytes = _cacheBytes;

    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final Set<String> cleanedPaths = {};

      try {
        final tempDir = await getTemporaryDirectory();
        if (await tempDir.exists() && cleanedPaths.add(tempDir.path)) {
          _cleanDirContents(tempDir);
        }
      } catch (_) {}

      try {
        final cacheDir = await getApplicationCacheDirectory();
        if (await cacheDir.exists() && cleanedPaths.add(cacheDir.path)) {
          _cleanDirContents(cacheDir);
        }
      } catch (_) {}

      await _loadCacheSize();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              freedBytes > 0
                  ? '缓存清理成功，已释放 ${storageSize(freedBytes)} 空间'
                  : '缓存已清理完毕',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清理缓存失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearingCache = false);
    }
  }

  void _cleanDirContents(Directory dir) {
    try {
      if (!dir.existsSync()) return;
      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        try {
          if (entity is File || entity is Link) {
            entity.deleteSync();
          } else if (entity is Directory) {
            entity.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _move() async {
    String? parent;
    if (Platform.isAndroid || Platform.isIOS) {
      final support = await getApplicationCacheDirectory();
      final directories = <String, String>{support.path: '应用内部存储'};
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectories() ?? [];
        for (var i = 0; i < external.length; i++) {
          directories[external[i].path] = i == 0
              ? '设备共享存储（应用目录）'
              : 'SD 卡 ${i + 1}（应用目录）';
        }
      } else {
        final documents = await getApplicationDocumentsDirectory();
        directories[documents.path] = '文件 App 可见目录';
      }
      if (!mounted) return;
      parent = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择下载位置'),
          children: [
            for (final entry in directories.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      );
    } else {
      parent = await FilePicker.getDirectoryPath(dialogTitle: '选择下载保存位置');
    }
    if (parent == null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('迁移已下载内容？'),
        content: Text(
          '将视频及短剧内容迁移到：\n$parent\n\n下载会先暂停，复制成功后清理旧目录。请保证目标有足够空间，并在完成后继续下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('迁移'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.moveDownloads(parent);
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDisplayDirectory(String raw) {
    if (raw.isEmpty) return '未设置';
    if (Platform.isIOS || raw.contains('/Containers/Data/Application/')) {
      if (raw.contains('/Documents/')) {
        return '应用沙盒：Documents/${raw.split('/Documents/').last}';
      }
      if (raw.contains('/Library/Caches/')) {
        return '应用沙盒：Library/Caches/${raw.split('/Library/Caches/').last}';
      }
      if (raw.contains('/Library/')) {
        return '应用沙盒：Library/${raw.split('/Library/').last}';
      }
      final segments = raw.split('/').where((s) => s.isNotEmpty).toList();
      return '应用专属沙盒：${segments.isNotEmpty ? segments.last : "downloads"}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_busy && !_isClearingCache,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('存储空间与下载目录'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '刷新用量',
              onPressed: (_busy || _isClearingCache) ? null : _refresh,
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  const Center(child: Text('正在执行迁移，请保持应用运行…')),
                  const SizedBox(height: 16),
                ],
                if (_error != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],

                // 1. 存储空间概览
                SettingsGroupCard(
                  title: '存储空间占用',
                  icon: Icons.pie_chart_outline_rounded,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_info != null) ...[
                            Text(
                              '离线短剧已占用 ${storageSize((_info!['bytes'] as num?)?.toInt() ?? 0)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '设备剩余空间：${storageSize((_info!['free'] as num?)?.toInt() ?? -1)} · 已下载 ${_info!['files'] ?? 0} 个短剧分集',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '在下载页删除不需要的分集，可直接释放设备存储空间。',
                              style: theme.textTheme.bodySmall,
                            ),
                          ] else ...[
                            const SizedBox(
                              height: 24,
                              child: Center(
                                child: Text('正在获取存储信息…'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // 2. 缓存管理
                SettingsGroupCard(
                  title: '应用缓存管理',
                  icon: Icons.cleaning_services_rounded,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.cached_rounded),
                      title: const Text('临时与图片缓存'),
                      subtitle: Text(
                        _isLoadingCache
                            ? '正在计算中…'
                            : '已占用空间：${storageSize(_cacheBytes)}',
                      ),
                      trailing: FilledButton.tonal(
                        key: const ValueKey('storage-clear-cache-button'),
                        onPressed: (_busy || _isClearingCache) ? null : _handleClearCache,
                        child: _isClearingCache
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('清理缓存'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        '包含网络海报缩略图、临时解密分片与运行缓存。清理后不影响追剧记录及已下载短剧。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),

                // 3. 当前下载保存目录
                if (_info != null)
                  SettingsGroupCard(
                    title: '下载保存目录',
                    icon: Icons.folder_outlined,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '当前保存路径',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              _formatDisplayDirectory(_info!['directory'] as String? ?? ''),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.copy_rounded),
                        title: const Text('复制保存路径'),
                        subtitle: const Text('点击复制下载目录路径到剪贴板'),
                        onTap: () {
                          final dir = _info!['directory'] as String? ?? '';
                          Clipboard.setData(ClipboardData(text: dir));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                Platform.isIOS
                                    ? '已复制 iOS 应用沙盒路径（系统安全隔离机制仅允许当前 App 读写）'
                                    : '已复制下载路径',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      if (widget.store.profile.admin)
                        ListTile(
                          leading: const Icon(Icons.drive_file_move_outlined),
                          title: const Text('更改并迁移目录'),
                          subtitle: const Text('将现有下载短剧完整迁移到新的存储位置'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _busy ? null : _move,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
