import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/js/js_source_models.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';
import 'package:THLRedLook/core/js/js_source_service.dart';
import 'package:THLRedLook/core/store/local_store.dart';

class JsSourcesPage extends StatefulWidget {
  const JsSourcesPage({
    super.key,
    required this.repository,
    required this.store,
    this.service,
  });

  final AppRepository repository;
  final LocalStore store;
  final JsSourceService? service;

  @override
  State<JsSourcesPage> createState() => _JsSourcesPageState();
}

class _JsSourcesPageState extends State<JsSourcesPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _scriptController = TextEditingController();

  late final JsSourceService _service =
      widget.service ??
      JsSourceService.current ??
      JsSourceService(widget.repository);

  @override
  void dispose() {
    _nameController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  Future<void> _handleSwitchSource(JsSourceMeta meta) async {
    final success = await _service.switchSource(meta.id);
    if (!mounted) return;
    if (success) {
      if (widget.store.allowsSource(meta.id)) {
        try {
          await widget.store.setSource(meta.id);
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已激活数据源插件：${meta.name} (${meta.id}.js)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('切换至数据源 ${meta.name} 失败'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleReload() async {
    await _service.reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已重新加载并扫描本地 JS 数据源'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showImportDialog() async {
    _nameController.text = 'custom_source.js';
    _scriptController.clear();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('导入 JS 数据源插件'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '支持 ECMAScript 标准插件。每个 JS 运行在独立沙箱中，拥有私有存储与隔离网络连接。',
                    style: TextStyle(fontSize: 12, color: AppColors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '文件名 (需以 .js 结尾)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _scriptController,
                    maxLines: 10,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'JavaScript 源码',
                      hintText:
                          'const meta = { id: "my_source", name: "我的源", ... };\n\nfunction getCategories() { ... }',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.hongguoRed,
              ),
              onPressed: () {
                if (_nameController.text.trim().isEmpty ||
                    _scriptController.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('验证并导入'),
            ),
          ],
        );
      },
    );

    if (result == true && mounted) {
      final fileName = _nameController.text.trim();
      final script = _scriptController.text;
      final ok = await _service.importScript(script, fileName);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功导入并装载 JS 数据源插件：$fileName'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('导入失败，请检查 JS 源码是否符合规范且包含 meta 元数据'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickAndImportFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['js'],
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final script = utf8.decode(bytes);

      if (script.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('所选 JS 文件内容为空'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final fileName = file.name.endsWith('.js')
          ? file.name
          : '${file.name}.js';
      final ok = await _service.importScript(script, fileName);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功导入外部插件：$fileName'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('导入失败，请检查 JS 源码是否符合规范且包含 meta 元数据'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('选取文件异常: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showUrlImportDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('网络订阅 / URL 导入插件'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '请输入远程 JavaScript 插件的直接下载地址 (如 GitHub Raw、Gist 或自建 CDN 链接)：',
                  style: TextStyle(fontSize: 12, color: AppColors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '插件脚本 URL',
                    hintText: 'https://example.com/source.js',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.hongguoRed,
              ),
              onPressed: () {
                final url = controller.text.trim();
                if (url.isNotEmpty) {
                  Navigator.pop(ctx, url);
                }
              },
              child: const Text('拉取并导入'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty && mounted) {
      final ok = await _service.importFromUrl(result);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('成功从网络拉取并装载 JS 数据源插件'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('网络拉取或导入失败，请检查 URL 可达性及脚本内容规范'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showPresetSelection() async {
    await showPresetSourceSelectionDialog(
      context: context,
      service: _service,
      onSourceChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _importPresets() async {
    final count = await importPresetSources(_service);
    if (!mounted) return;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已导入 $count 个测试数据源插件（当前测试包专用）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteSource(JsSourceMeta meta) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.hongguoRed),
            SizedBox(width: 8),
            Text('删除数据源'),
          ],
        ),
        content: Text(
          '确定要删除数据源「${meta.name}」(${meta.id}.js) 吗？\n删除后本地脚本文件将被移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.hongguoRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final ok = await _service.removeSource(meta.id);
      if (!mounted) return;
      if (ok) {
        if (widget.store.source == meta.id) {
          final nextSource = _service.activeSourceId.isNotEmpty
              ? _service.activeSourceId
              : (widget.store.sources.isNotEmpty
                    ? widget.store.sources.first.id
                    : 'hongguo');
          try {
            await widget.store.setSource(nextSource);
          } catch (_) {}
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功删除数据源：${meta.name}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除数据源 ${meta.name} 失败'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmClearAllSources() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.hongguoRed),
            SizedBox(width: 8),
            Text('清空所有数据源'),
          ],
        ),
        content: const Text('确定要清空所有已导入的 JS 数据源插件吗？\n此操作将删除本地所有插件脚本文件，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.hongguoRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('全部清空'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _service.clearAll();
      if (!mounted) return;
      try {
        await widget.store.setSource('hongguo');
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已清空所有数据源插件'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('JS 数据源插件管理'),
        actions: [
          IconButton(
            tooltip: '重载插件',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _handleReload,
          ),
          PopupMenuButton<String>(
            key: const ValueKey('js-sources-more-actions'),
            tooltip: '更多操作',
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: isDark
                ? AppColors.darkSurfaceElevated
                : AppColors.lightSurface,
            elevation: 4,
            onSelected: (action) {
              switch (action) {
                case 'select_presets':
                  _showPresetSelection();
                  break;
                case 'presets':
                  _importPresets();
                  break;
                case 'url':
                  _showUrlImportDialog();
                  break;
                case 'file':
                  _pickAndImportFile();
                  break;
                case 'code':
                  _showImportDialog();
                  break;
                case 'clear_all':
                  _confirmClearAllSources();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'select_presets',
                child: Row(
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      size: 20,
                      color: AppColors.hongguoRed,
                    ),
                    SizedBox(width: 12),
                    Text('选择预设源分别导入'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'presets',
                child: Row(
                  children: [
                    Icon(
                      Icons.flash_on_rounded,
                      size: 20,
                      color: AppColors.hongguoRed,
                    ),
                    SizedBox(width: 12),
                    Text('一键导入测试预设源'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'url',
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('网络订阅导入'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'file',
                child: Row(
                  children: [
                    Icon(Icons.file_open_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('从外部文件选取插件'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'code',
                child: Row(
                  children: [
                    Icon(Icons.code_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('粘贴插件源码导入'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever_rounded,
                      size: 20,
                      color: AppColors.hongguoRed,
                    ),
                    SizedBox(width: 12),
                    Text(
                      '清空所有数据源',
                      style: TextStyle(color: AppColors.hongguoRed),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          final sources = _service.sources;
          final activeId = _service.activeSourceId;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 架构说明卡片
              Container(
                decoration: BoxDecoration(
                  gradient: isDark ? AppGradients.surfaceCard : null,
                  color: isDark ? null : AppColors.greyLight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x26FFFFFF)
                        : AppColors.lightBorder,
                    width: 0.8,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.accentSubtle12,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.hub_rounded,
                              color: AppColors.hongguoRed,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '原生独立沙箱引擎 (v1.0.1)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.hongguoRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '所有站源均已解耦为标准 JavaScript 插件。各插件在原生隔离上下文中运行，网络请求、加密解密、DOM 解析互不干扰，单源异常不会影响整个应用。切换数据源即切换执行的 JS 插件。',
                        style: TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              Text(
                '已装载的外部 JS 插件 (${sources.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.white : AppColors.darkBackground,
                ),
              ),
              const SizedBox(height: 12),

              if (sources.isEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.greyLight,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 36,
                      horizontal: 20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurfaceHighest
                                : AppColors.lightSurfaceHigh,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.extension_off_rounded,
                            size: 40,
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '当前未导入任何数据源插件',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '本应用出厂不内置任何站源，请从外部导入或添加 .js 插件。各插件在沙箱内独立运行、互不干扰。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.grey,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              key: const ValueKey('btn-select-preset-import'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.hongguoRed,
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _showPresetSelection,
                              icon: const Icon(
                                Icons.checklist_rounded,
                                size: 18,
                              ),
                              label: const Text('选择预设源分别导入'),
                            ),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _importPresets,
                              icon: const Icon(
                                Icons.flash_on_rounded,
                                size: 18,
                              ),
                              label: const Text('一键导入全部预设'),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.hongguoRed,
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _pickAndImportFile,
                              icon: const Icon(
                                Icons.file_open_rounded,
                                size: 18,
                              ),
                              label: const Text('选择外部 .js 插件'),
                            ),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _showUrlImportDialog,
                              icon: const Icon(Icons.link_rounded, size: 18),
                              label: const Text('网络链接订阅'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: const StadiumBorder(),
                              ),
                              onPressed: _showImportDialog,
                              icon: const Icon(Icons.code_rounded, size: 18),
                              label: const Text('粘贴插件源码'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...sources.map((meta) {
                  final isActive = meta.id == activeId;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: isActive
                        ? AppColors.accentSubtle12
                        : (isDark ? AppColors.darkSurface : AppColors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: isActive
                            ? AppColors.hongguoRed
                            : (isDark
                                  ? AppColors.darkBorder
                                  : AppColors.greyLight),
                        width: isActive ? 1.5 : 0.8,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _handleSwitchSource(meta),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: isActive
                                        ? AppGradients.primary
                                        : null,
                                    color: isActive
                                        ? null
                                        : (isDark
                                              ? AppColors.darkSurfaceHighest
                                              : AppColors.lightSurfaceHighest),
                                    shape: BoxShape.circle,
                                    boxShadow: isActive
                                        ? AppShadows.pillGlow
                                        : null,
                                  ),
                                  child: Icon(
                                    Icons.javascript_rounded,
                                    color: isActive
                                        ? AppColors.white
                                        : AppColors.hongguoRed,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            meta.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: isActive
                                                  ? AppColors.hongguoRed
                                                  : null,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? AppColors.darkSurfaceHighest
                                                  : AppColors.greyLight,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'v${meta.version}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '文件: ${meta.id}.js · 作者: ${meta.author.isNotEmpty ? meta.author : "内置"}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: AppGradients.primary,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: AppShadows.pillGlow,
                                        ),
                                        child: const Text(
                                          '当前激活',
                                          style: TextStyle(
                                            color: AppColors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else
                                      TextButton(
                                        onPressed: () =>
                                            _handleSwitchSource(meta),
                                        child: const Text(
                                          '激活',
                                          style: TextStyle(
                                            color: AppColors.hongguoRed,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      key: ValueKey('delete-source-${meta.id}'),
                                      tooltip: '删除数据源',
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20,
                                        color: AppColors.grey,
                                      ),
                                      onPressed: () =>
                                          _confirmDeleteSource(meta),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (meta.description.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                meta.description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            if (meta.features.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: meta.features.map((feat) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentSubtle12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      feat,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.hongguoRed,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
