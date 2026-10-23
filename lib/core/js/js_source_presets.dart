// 预置短剧与影视 CatPawOpen Spider 数据源插件定义。
// 适配标准 CatPawOpen / CatVodOpen JS 规范，可在端侧沙箱及第三方播放器（如猫爪等）中独立运行。

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/core/js/js_source_service.dart';

class PresetJsSource {
  final String id;
  final String fileName;
  final String name;
  final String description;
  final String assetPath;

  const PresetJsSource({
    required this.id,
    required this.fileName,
    required this.name,
    required this.description,
    required this.assetPath,
  });

  /// 异步读取内嵌 JS 脚本内容
  /// 优先使用 Flutter rootBundle 从 Asset 资源束中加载；
  /// 在单元测试或无 Binding 纯 Dart 环境中，自动回退到本地文件加载。
  Future<String> loadScript() async {
    try {
      return await rootBundle.loadString(assetPath);
    } catch (_) {
      final file = File(assetPath);
      if (await file.exists()) {
        return await file.readAsString();
      }
      rethrow;
    }
  }

  /// 同步读取脚本（主要用于脱机、测试或需要同步获取的极端场景）
  String loadScriptSync() {
    final file = File(assetPath);
    return file.readAsStringSync();
  }

  /// 向后兼容 getter（建议使用 loadScript）
  @Deprecated('Use loadScript() instead')
  String get script => loadScriptSync();
}

const List<PresetJsSource> kPresetJsSources = [
  PresetJsSource(
    id: 'hongguo',
    fileName: 'hongguo.js',
    name: '官方免费短剧',
    description: '官方首发短剧源，包含海量都市爽文、战神回归、现代甜宠短剧',
    assetPath: 'assets/sources/hongguo.js',
  ),
];

/// 批量一键导入预设插件（仅供当前测试包使用）
Future<int> importPresetSources(JsSourceService service) async {
  int count = 0;
  for (final preset in kPresetJsSources) {
    final script = await preset.loadScript();
    final ok = await service.importScript(script, preset.fileName);
    if (ok) {
      count++;
    }
  }
  return count;
}

/// 根据 ID 或文件名查找特定的预设数据源
PresetJsSource? findPresetSource(String idOrFileName) {
  for (final preset in kPresetJsSources) {
    if (preset.id == idOrFileName ||
        preset.fileName == idOrFileName ||
        preset.fileName == '$idOrFileName.js') {
      return preset;
    }
  }
  return null;
}

/// 单独导入指定的预设数据源
Future<bool> importSinglePresetSource(
  JsSourceService service,
  String sourceId,
) async {
  final preset = findPresetSource(sourceId);
  if (preset == null) return false;
  final script = await preset.loadScript();
  return await service.importScript(script, preset.fileName);
}

/// 弹出预设数据源选择与分别导入对话框，支持逐个单独导入测试或一键导入全部
Future<void> showPresetSourceSelectionDialog({
  required BuildContext context,
  required JsSourceService service,
  VoidCallback? onSourceChanged,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final sources = service.sources;
          final activeId = service.activeSourceId;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 8,
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.accentSubtle12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.flash_on_rounded,
                    color: AppColors.hongguoRed,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '预置数据源分别导入',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '可分别单独导入任意预置 JS 插件，验证多源独立沙箱与数据隔离；亦可一键全量装载：',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.grey,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ...kPresetJsSources.map((preset) {
                      final isImported = sources.any((s) => s.id == preset.id);
                      final isActive = activeId == preset.id;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurfaceHighest
                              : AppColors.lightSurfaceHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive
                                ? AppColors.hongguoRed
                                : (isDark
                                      ? AppColors.darkBorder
                                      : AppColors.greyLight),
                            width: isActive ? 1.5 : 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive
                                    ? AppColors.hongguoRed
                                    : (isDark
                                          ? AppColors.darkSurface
                                          : AppColors.white),
                              ),
                              child: Icon(
                                Icons.javascript_rounded,
                                color: isActive
                                    ? AppColors.white
                                    : AppColors.hongguoRed,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isActive
                                          ? AppColors.hongguoRed
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${preset.fileName} · ${preset.description}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.hongguoRed,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  '已激活',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if (isImported)
                              FilledButton.tonal(
                                key: ValueKey('activate-preset-${preset.id}'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                                onPressed: () async {
                                  await service.switchSource(preset.id);
                                  setDialogState(() {});
                                  onSourceChanged?.call();
                                },
                                child: const Text(
                                  '激活',
                                  style: TextStyle(fontSize: 12),
                                ),
                              )
                            else
                              FilledButton(
                                key: ValueKey('import-preset-${preset.id}'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.hongguoRed,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                                onPressed: () async {
                                  final ok = await importSinglePresetSource(
                                    service,
                                    preset.id,
                                  );
                                  if (ok) {
                                    if (service.activeSourceId.isEmpty) {
                                      await service.switchSource(preset.id);
                                    }
                                    setDialogState(() {});
                                    onSourceChanged?.call();
                                    if (dialogCtx.mounted) {
                                      ScaffoldMessenger.of(
                                        dialogCtx,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '已单独导入数据源：${preset.name}',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text(
                                  '导入',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton.tonal(
                key: const ValueKey('import-all-presets'),
                onPressed: () async {
                  final count = await importPresetSources(service);
                  if (service.activeSourceId.isEmpty) {
                    await service.switchSource('hongguo');
                  }
                  setDialogState(() {});
                  onSourceChanged?.call();
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(
                        content: Text('已成功批量导入全部 $count 个预置数据源'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('一键导入全部'),
              ),
            ],
          );
        },
      );
    },
  );
}
