import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/pages/settings/resource_settings_page.dart';
import 'package:THLRedLook/utils/settings/settings_backup_helper.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({
    super.key,
    required this.store,
    required this.repository,
  });

  final LocalStore store;
  final AppRepository repository;

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  bool _busy = false;
  String? _message;

  Future<void> _backup(bool restore) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!restore) {
        final saved = await SettingsBackupHelper.exportBackup(widget.store);
        if (saved != null && mounted) {
          setState(() => _message = '配置备份已成功导出保存');
        }
      } else {
        final success = await SettingsBackupHelper.restoreBackup(context, widget.store);
        if (success && mounted) {
          setState(() => _message = '配置备份恢复成功');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _message = '操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('备份与恢复'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Card(
            elevation: 0,
            color: isDark ? AppColors.darkCard : AppColors.greyLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppColors.accentSubtle12,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.settings_backup_restore_rounded,
                      color: AppColors.hongguoRed,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '本地数据安全备份',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '追剧记录、自定义偏好及用户档案完整存储于设备端，支持跨设备导入迁移。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            '备份操作',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.hongguoRed,
            ),
          ),
          const SizedBox(height: 8),

          Card(
            elevation: 0,
            color: isDark ? AppColors.darkCard : AppColors.greyLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('导出完整配置备份'),
                  subtitle: const Text('将当前设备追剧历史与设置导出为 JSON 备份文件'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : () => _backup(false),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: const Text('从备份文件恢复配置'),
                  subtitle: const Text('读取并恢复先前导出的 JSON 备份数据'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy ? null : () => _backup(true),
                ),
              ],
            ),
          ),

          if (widget.store.profile.admin) ...[
            const SizedBox(height: 20),
            Text(
              '网络调度与资源高级设置',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.hongguoRed,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              color: isDark ? AppColors.darkCard : AppColors.greyLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: const Icon(Icons.settings_ethernet_rounded),
                title: const Text('网络请求与资源调度'),
                subtitle: const Text('代理服务器、请求频次间隔与下载并发数配置'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ResourceSettingsScreen(
                      repository: widget.repository,
                      store: widget.store,
                    ),
                  ),
                ),
              ),
            ),
          ],

          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),

          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.accentSubtle12,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.hongguoRed, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _message!,
                        style: const TextStyle(
                          color: AppColors.hongguoRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
