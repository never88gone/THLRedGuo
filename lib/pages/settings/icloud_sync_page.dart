import 'package:flutter/material.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/core/sync/icloud_sync_service.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class ICloudSyncPage extends StatefulWidget {
  const ICloudSyncPage({super.key, required this.store});

  final LocalStore store;

  @override
  State<ICloudSyncPage> createState() => _ICloudSyncPageState();
}

class _ICloudSyncPageState extends State<ICloudSyncPage> {
  final _service = ICloudSyncService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = _service.isSyncEnabled(widget.store.preferences);

    return Scaffold(
      appBar: AppBar(
        title: const Text('iCloud 云端同步'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. 顶部 Hero Banner
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
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: AppColors.accentSubtle12,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: AppColors.hongguoRed,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Apple 生态无缝互通',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '通过 Apple 官方 iCloud 键值存储，在登录同一 Apple ID 的 iPhone、iPad、Mac 与 Apple TV 设备间实时双向同步。',
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

          // 2. 开关卡片
          Card(
            elevation: 0,
            color: isDark ? AppColors.darkCard : AppColors.greyLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile.adaptive(
              key: const ValueKey('icloud-sync-switch'),
              secondary: Icon(
                enabled ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                color: enabled ? AppColors.hongguoRed : theme.iconTheme.color,
              ),
              title: const Text(
                '启用 iCloud 同步',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                enabled
                    ? '已开启 · 自动在云端同步配置信息、观看记录与追剧信息'
                    : '已停用 · 数据仅保存在当前设备本地',
              ),
              value: enabled,
              activeTrackColor: AppColors.hongguoRed,
              onChanged: (val) async {
                await _service.setSyncEnabled(val, widget.store);
              },
            ),
          ),
          const SizedBox(height: 16),

          // 3. 状态与立即同步操作
          if (enabled) ...[
            Text(
              '同步状态',
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前状态：${_service.lastStatusMessage}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    if (_service.lastSyncDate != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '上次同步：${_formatDateTime(_service.lastSyncDate!)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('icloud-manual-sync-btn'),
                        onPressed: _service.isSyncing
                            ? null
                            : () => _service.syncWithCloud(widget.store),
                        icon: _service.isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync_rounded),
                        label: Text(_service.isSyncing ? '正在同步...' : '立即与云端同步'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.hongguoRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 4. 同步项目清单说明
          Text(
            '同步数据范围',
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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.history_rounded, color: AppColors.hongguoRed),
                    title: Text('观看记录 (Watch History)'),
                    subtitle: Text('短剧播放集数、进度秒数与最后观看时间，跨端自动接续起播'),
                  ),
                  const Divider(height: 1, indent: 56),
                  const ListTile(
                    leading: Icon(Icons.bookmark_added_rounded, color: AppColors.hongguoRed),
                    title: Text('追剧信息 (Followed Dramas)'),
                    subtitle: Text('追剧列表、在追/追完状态，多设备无缝保持更新'),
                  ),
                  const Divider(height: 1, indent: 56),
                  const ListTile(
                    leading: Icon(Icons.tune_rounded, color: AppColors.hongguoRed),
                    title: Text('配置信息 (Preferences)'),
                    subtitle: Text('默认主源设置、默认播放倍速、弹幕开启偏好设置'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }
}
