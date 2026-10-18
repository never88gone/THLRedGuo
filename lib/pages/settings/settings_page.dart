import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/theme/app_theme.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/settings/resource_settings_page.dart';
import 'package:THLRedLook/pages/sources/sources_page.dart';
import 'package:THLRedLook/views/sources/source_switcher_sheet.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/settings/settings_group_view.dart';
import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/utils/settings/settings_backup_helper.dart';
import 'package:THLRedLook/pages/privacy/privacy_settings_page.dart';
import 'package:THLRedLook/pages/about/about_page.dart';
import 'package:THLRedLook/pages/about/contact_page.dart';
import 'package:THLRedLook/pages/about/third_party_page.dart';
import 'package:THLRedLook/pages/settings/storage_page.dart';
import 'package:THLRedLook/pages/settings/js_sources_page.dart';
import 'package:THLRedLook/pages/settings/source_diagnostics_page.dart';

export 'storage_page.dart' show storageSize;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.store,
  });

  final AppRepository repository;
  final LocalStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  String? _message;
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version.isNotEmpty ? info.version : '1.0.0';
        });
      }
    } catch (_) {
      // 保持默认 1.0.0
    }
  }

  Future<void> _chooseTheme() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('外观主题'),
        children: [
          RadioGroup<String>(
            groupValue: widget.store.themeMode,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ['light', 'dark', 'system'])
                  RadioListTile<String>(
                    value: mode,
                    title: Text(AppTheme.label(mode)),
                    subtitle: mode == 'system'
                        ? const Text('随设备的深色模式自动切换')
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      await saveUserChange(context, () => widget.store.setThemeMode(selected));
    }
  }

  Future<void> _chooseDefaultSpeed() async {
    final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final selected = await showModalBottomSheet<double>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '默认播放倍速',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final s in speeds)
              ListTile(
                title: Text('${s}x${s == 1.0 ? ' (正常速度)' : ''}'),
                trailing: widget.store.playbackPreferences.speed == s
                    ? const Icon(Icons.check_rounded, color: AppColors.hongguoRed)
                    : null,
                onTap: () => Navigator.pop(context, s),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      final updated = widget.store.playbackPreferences.copyWith(speed: selected);
      await saveUserChange(context, () => widget.store.setPlaybackPreferences(updated));
    }
  }

  Future<void> _chooseDefaultQuality() async {
    final qualities = [
      {'label': '自动 · 优先原画', 'value': 0},
      {'label': '1080P · 超清', 'value': 1080},
      {'label': '720P · 高清', 'value': 720},
      {'label': '480P · 标清', 'value': 480},
    ];
    final selected = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '默认起播画质',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final q in qualities)
              ListTile(
                title: Text(q['label'] as String),
                trailing: widget.store.playbackPreferences.quality == (q['value'] as int)
                    ? const Icon(Icons.check_rounded, color: AppColors.hongguoRed)
                    : null,
                onTap: () => Navigator.pop(context, q['value'] as int),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      final updated = widget.store.playbackPreferences.copyWith(quality: selected);
      await saveUserChange(context, () => widget.store.setPlaybackPreferences(updated));
    }
  }

  Future<void> _backup(bool restore) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!restore) {
        final saved = await SettingsBackupHelper.exportBackup(widget.store);
        if (saved != null && mounted) setState(() => _message = '备份已成功保存');
      } else {
        await SettingsBackupHelper.restoreBackup(context, widget.store);
      }
    } catch (e) {
      if (mounted) setState(() => _message = '操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final playPrefs = widget.store.playbackPreferences;
        final qualityLabel = switch (playPrefs.quality) {
          1080 => '1080P 超清',
          720 => '720P 高清',
          480 => '480P 标清',
          _ => '自动（优先原画）',
        };

        return Scaffold(
          appBar: AppBar(
            title: const Text('设置与偏好'),
            centerTitle: true,
          ),
          body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // 1. 隐私安全
          SettingsGroupCard(
            title: '隐私安全',
            icon: Icons.security_rounded,
            children: [
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('手势密码与隐私短剧库'),
                subtitle: Text(
                  PrivacyLockController(widget.store.preferences).enabled
                      ? '已启用手势解锁 · 保护私密短剧'
                      : '手势隐私锁 · 隐私短剧库密码保护',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PrivacySettingsPage(
                        controller: PrivacyLockController(widget.store.preferences),
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),

          // 2. 短剧播放偏好
          SettingsGroupCard(
            title: '短剧播放设置',
            icon: Icons.play_circle_outline_rounded,
            children: [
              ListTile(
                leading: const Icon(Icons.hd_outlined),
                title: const Text('默认起播画质'),
                subtitle: Text(qualityLabel),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _chooseDefaultQuality,
              ),
              ListTile(
                leading: const Icon(Icons.speed_rounded),
                title: const Text('默认播放倍速'),
                subtitle: Text('${playPrefs.speed}x'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _chooseDefaultSpeed,
              ),
              ListTile(
                key: const ValueKey('settings-switch-source'),
                leading: const Icon(Icons.swap_horiz_rounded),
                title: const Text('切换当前数据源'),
                subtitle: Text('当前正在使用：${SourceSite.byId(widget.store.source).name} · 轻触切换可用站源'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showSourceSwitcherSheet(
                  context,
                  store: widget.store,
                  onSelect: (site) {
                    saveUserChange(context, () => widget.store.setSource(site.id));
                  },
                ),
              ),
              ListTile(
                key: const ValueKey('settings-js-sources'),
                leading: const Icon(Icons.javascript_rounded),
                title: const Text('JS 数据源插件管理'),
                subtitle: const Text('独立沙箱运行 · 数据源列表、导入与删除管理'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => JsSourcesPage(
                      repository: widget.repository,
                      store: widget.store,
                    ),
                  ),
                ),
              ),
              if (widget.repository.supportsSourceManagement && (widget.store.isZhenguojianActivated || widget.store.sources.length > 1))
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('站源测速与连通性检测'),
                  subtitle: const Text('多源站启用状态、健康诊断与网络测速'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SourcesScreen(
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // 3. 存储与下载
          SettingsGroupCard(
            title: '缓存与离线下载',
            icon: Icons.download_rounded,
            children: [
              if (widget.store.canDownload) ...[
                ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('离线下载偏好'),
                  subtitle: Text(widget.store.downloadPreferences.qualityLabel),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => DownloadPreferencesScreen(store: widget.store),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.storage_rounded),
                  title: const Text('存储空间与下载目录'),
                  subtitle: const Text('查看离线短剧空间占用并迁移保存路径'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => StorageScreen(
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.screen_lock_portrait_rounded),
                  title: const Text('禁止自动锁屏'),
                  subtitle: const Text('保持屏幕常亮，防止离线下载与挂机时设备自动息屏休眠'),
                  value: widget.store.keepScreenOn,
                  activeThumbColor: AppColors.hongguoRed,
                  activeTrackColor: AppColors.accentTrack35,
                  onChanged: (val) async {
                    await saveUserChange(
                      context,
                      () => widget.store.setKeepScreenOn(val),
                    );
                  },
                ),
              ],
            ],
          ),

          // 4. 外观视觉
          SettingsGroupCard(
            title: '外观与主题体验',
            icon: Icons.palette_outlined,
            children: [
              ListTile(
                key: const ValueKey('theme-setting'),
                leading: const Icon(Icons.brightness_6_rounded),
                title: const Text('主题外观'),
                subtitle: Text(AppTheme.label(widget.store.themeMode)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _chooseTheme,
              ),
              ListTile(
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: AppColors.hongguoRed,
                    shape: BoxShape.circle,
                  ),
                ),
                title: const Text('品牌视觉'),
                subtitle: const Text('经典活力红短剧主题色'),
                trailing: const Icon(Icons.done_all_rounded, color: AppColors.hongguoRed),
              ),
            ],
          ),

          // 5. 设备同步与高级管理
          if (widget.store.profile.admin)
            SettingsGroupCard(
              title: '高级配置与数据管理',
              icon: Icons.tune_rounded,
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_ethernet_rounded),
                  title: const Text('网络请求与资源调度'),
                  subtitle: const Text('代理服务器、请求频次间隔与下载并发数'),
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
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('导出完整配置备份'),
                  subtitle: const Text('将当前设备追剧历史与设置导出为 JSON 备份'),
                  onTap: _busy ? null : () => _backup(false),
                ),
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: const Text('从备份文件恢复配置'),
                  subtitle: const Text('读取并恢复导出的 JSON 配置'),
                  onTap: _busy ? null : () => _backup(true),
                ),
              ],
            ),

          // 6. 系统诊断与关于
          SettingsGroupCard(
            title: '关于与系统诊断',
            icon: Icons.info_outline_rounded,
            children: [
              ListTile(
                key: const ValueKey('settings-source-diagnostics'),
                leading: const Icon(Icons.network_check_rounded),
                title: const Text('数据源诊断'),
                subtitle: const Text('检查网络连接、搜索与详情，复制脱敏报告'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SourceDiagnosticsPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_rounded),
                title: const Text('播放诊断日记'),
                subtitle: const Text('查看原生解码、流媒体握手与解密运行轨迹'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => DiaryService.showDiaryDialog(context),
              ),
              ListTile(
                key: const ValueKey('settings-contact-entry'),
                leading: const Icon(Icons.forum_outlined),
                title: const Text('联系方式'),
                subtitle: const Text('Telegram 官方交流与反馈 · 直接跳转打开'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ContactPage(),
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('settings-third-party-entry'),
                leading: const Icon(Icons.extension_outlined),
                title: const Text('第三方开源组件'),
                subtitle: const Text('核心开源库、开源许可证与授权声明'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ThirdPartyPage(),
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('settings-about-entry'),
                leading: const Icon(Icons.verified_outlined),
                title: const Text('关于 糖葫芦Haw'),
                subtitle: Text(_appVersion),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AboutPage(store: widget.store),
                  ),
                ),
              ),
            ],
          ),

          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
      },
    );
  }
}
