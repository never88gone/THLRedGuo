import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:THLRedLook/core/update/app_update_service.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 弹出更新对话框
Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdateInfo info,
) =>
    showDialog<void>(
      context: context,
      builder: (_) => AppUpdateDialog(info: info),
    );

/// 便捷触发检查更新并给出 UI 反馈
Future<void> triggerCheckUpdate(
  BuildContext context, {
  bool silentIfNoUpdate = false,
}) async {
  if (!AppUpdateService.isSupportedPlatform) {
    if (!silentIfNoUpdate) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('iOS 与 tvOS 端通过 TestFlight 自动更新'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
    return;
  }

  if (!silentIfNoUpdate) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('正在检查新版本...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  try {
    final info = await AppUpdateService.instance.checkUpdate();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (info.hasUpdate) {
      await showAppUpdateDialog(context, info);
    } else if (!silentIfNoUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('当前已是最新版本 (${info.displayCurrentVersion})'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (!silentIfNoUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('检查更新失败，请检查网络或稍后重试'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, required this.info});

  final AppUpdateInfo info;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  late UpdateAsset? _selectedAsset;
  bool _showOtherAssets = false;

  @override
  void initState() {
    super.initState();
    _selectedAsset = widget.info.primaryAsset;
  }

  IconData _platformIcon() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return Icons.android_rounded;
      case TargetPlatform.windows:
        return Icons.desktop_windows_rounded;
      case TargetPlatform.macOS:
        return Icons.laptop_mac_rounded;
      case TargetPlatform.iOS:
        return Icons.phone_iphone_rounded;
      default:
        return Icons.system_update_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final info = widget.info;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.hongguoRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _platformIcon(),
              color: AppColors.hongguoRed,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '发现新版本',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.hongguoRed,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${info.displayCurrentVersion} → ${info.displayRemoteVersion}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.hongguoRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 420,
          maxHeight: 460,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 安装包信息卡片
              if (_selectedAsset != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.greyLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.download_rounded, size: 16, color: AppColors.hongguoRed),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _selectedAsset!.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedAsset!.formattedSize.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              _selectedAsset!.formattedSize,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textTheme.bodySmall?.color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_selectedAsset!.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _selectedAsset!.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 多安装包选项展开（如 Android 其它架构）
              if (info.availableAssets.length > 1) ...[
                InkWell(
                  onTap: () {
                    setState(() {
                      _showOtherAssets = !_showOtherAssets;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _showOtherAssets ? '收起其他架构包' : '选择其他设备架构包 (${info.availableAssets.length})',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Icon(
                          _showOtherAssets ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showOtherAssets) ...[
                  const SizedBox(height: 6),
                  ...info.availableAssets.map((asset) {
                    final isCur = asset.downloadUrl == _selectedAsset?.downloadUrl;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: isCur
                            ? AppColors.hongguoRed.withValues(alpha: 0.08)
                            : (isDark ? AppColors.darkCard : AppColors.greyLight),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isCur ? AppColors.hongguoRed : Colors.transparent,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          dense: true,
                          title: Text(
                            asset.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${asset.description}${asset.formattedSize.isNotEmpty ? " · ${asset.formattedSize}" : ""}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: isCur
                              ? const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.hongguoRed)
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedAsset = asset;
                            });
                          },
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 8),
              ],

              // 更新日志
              Text(
                '更新日志',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.greyLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    info.releaseNotes.isNotEmpty
                        ? info.releaseNotes
                        : '本次更新包含体验优化及问题修复。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后再说'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.file_download_rounded, size: 18),
          label: Text(_selectedAsset != null ? '立即下载' : '前往下载'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.hongguoRed,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () {
            final targetUrl = _selectedAsset?.downloadUrl ?? info.htmlUrl;
            AppUpdateService.openDownloadUrl(
              context,
              targetUrl,
              fallbackLabel: _selectedAsset?.name ?? '新版本',
            );
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
