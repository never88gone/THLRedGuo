import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/about/about_page.dart';
import 'package:THLRedLook/pages/about/app_intro_page.dart';
import 'package:THLRedLook/pages/about/contact_page.dart';
import 'package:THLRedLook/pages/about/third_party_page.dart';
import 'package:THLRedLook/pages/privacy/privacy_settings_page.dart';
import 'package:THLRedLook/pages/settings/backup_settings_page.dart';
import 'package:THLRedLook/pages/settings/icloud_sync_page.dart';
import 'package:THLRedLook/core/sync/icloud_sync_service.dart';
import 'package:THLRedLook/pages/settings/display_mode_page.dart';
import 'package:THLRedLook/pages/settings/js_sources_page.dart';
import 'package:THLRedLook/pages/settings/playback_settings_page.dart';
import 'package:THLRedLook/pages/settings/resource_settings_page.dart';
import 'package:THLRedLook/pages/settings/source_diagnostics_page.dart';
import 'package:THLRedLook/pages/settings/storage_page.dart';
import 'package:THLRedLook/pages/settings/theme_settings_page.dart';
import 'package:THLRedLook/pages/sources/sources_page.dart';
import 'package:THLRedLook/utils/build/app_build.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/theme/app_theme.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/settings/settings_group_view.dart';
import 'package:THLRedLook/views/sources/source_switcher_sheet.dart';

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

  String _displayModeLabel(String mode) {
    return switch (mode) {
      'television' => '电视 / 遥控器',
      'standard' => '手机 / 电脑',
      _ => '自动识别设备',
    };
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
          _ => '自动起播',
        };

        return Scaffold(
          appBar: AppBar(
            title: const Text('设置'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              // 1. 界面与显示（收纳原有的页面模式、外观主题）
              SettingsGroupCard(
                title: '界面与显示',
                icon: Icons.dashboard_customize_rounded,
                children: [
                  ListTile(
                    key: const ValueKey('settings-display-mode-entry'),
                    leading: const Icon(Icons.devices_rounded),
                    title: const Text('页面模式'),
                    subtitle: Text('当前：${_displayModeLabel(widget.store.displayMode)} · 电视、手机或电脑适配'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => DisplayModePage(store: widget.store),
                      ),
                    ),
                  ),
                  ListTile(
                    key: const ValueKey('settings-theme-entry'),
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('外观与主题'),
                    subtitle: Text('当前：${AppTheme.label(widget.store.themeMode)} · 深色模式与品牌色彩'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ThemeSettingsPage(store: widget.store),
                      ),
                    ),
                  ),
                ],
              ),

              // 2. 短剧播放
              SettingsGroupCard(
                title: '短剧播放',
                icon: Icons.play_circle_outline_rounded,
                children: [
                  ListTile(
                    key: const ValueKey('settings-playback-entry'),
                    leading: const Icon(Icons.tune_rounded),
                    title: const Text('播放设置'),
                    subtitle: Text(
                      '默认 $qualityLabel · ${playPrefs.speed}x · 弹幕${playPrefs.danmaku ? "开启" : "关闭"}${playPrefs.pictureInPicture ? " · 画中画开启" : ""}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PlaybackSettingsPage(store: widget.store),
                      ),
                    ),
                  ),
                  if (defaultTargetPlatform == TargetPlatform.android ||
                      defaultTargetPlatform == TargetPlatform.iOS) ...[
                    const Divider(height: 1, indent: 56),
                    SwitchListTile.adaptive(
                      key: const ValueKey('settings-main-pip-switch'),
                      secondary: const Icon(Icons.picture_in_picture_alt_rounded),
                      title: const Text('画中画模式'),
                      subtitle: Text(
                        playPrefs.pictureInPicture
                            ? '已开启画中画（切出应用或点击按钮悬浮播放）'
                            : '已关闭（开启后可在播放器使用画中画小窗）',
                      ),
                      value: playPrefs.pictureInPicture,
                      activeThumbColor: AppColors.white,
                      activeTrackColor: AppColors.hongguoRed,
                      onChanged: (val) async {
                        final updated = playPrefs.copyWith(pictureInPicture: val);
                        await saveUserChange(
                          context,
                          () => widget.store.setPlaybackPreferences(updated),
                        );
                      },
                    ),
                  ],
                ],
              ),

              // 3. 数据源与插件
              SettingsGroupCard(
                title: '数据源与插件',
                icon: Icons.hub_outlined,
                children: [
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
                  ListTile(
                    key: const ValueKey('settings-source-diagnostics'),
                    leading: const Icon(Icons.network_check_rounded),
                    title: const Text('网络与数据源诊断'),
                    subtitle: const Text('检测网络连通性、DNS、JS引擎与搜索详情，生成详细报告'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SourceDiagnosticsPage(),
                      ),
                    ),
                  ),
                  if (widget.repository.supportsSourceManagement &&
                      (widget.store.isZhenguojianActivated || widget.store.sources.length > 1))
                    ListTile(
                      leading: const Icon(Icons.speed_rounded),
                      title: const Text('站源管理'),
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

              // 4. 离线与存储
              if (widget.store.canDownload)
                SettingsGroupCard(
                  title: '离线与存储',
                  icon: Icons.download_rounded,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.video_settings_rounded),
                      title: const Text('离线下载偏好'),
                      subtitle: Text('清晰度：${widget.store.downloadPreferences.qualityLabel}'),
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
                  ],
                ),

              // 5. 数据与备份（收纳原有的设置与备份功能）
              SettingsGroupCard(
                title: '数据与备份',
                icon: Icons.settings_backup_restore_rounded,
                children: [
                  if (ICloudSyncService.instance.isSupported) ...[
                    ListTile(
                      key: const ValueKey('settings-icloud-sync-entry'),
                      leading: const Icon(Icons.cloud_sync_rounded),
                      title: const Text('iCloud 云端同步'),
                      subtitle: Text(
                        ICloudSyncService.instance.isSyncEnabled(widget.store.preferences)
                            ? '已开启 · 自动在 iOS、macOS 与 Apple TV 间同步'
                            : '已停用 · 轻触开启苹果生态多端同步',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ICloudSyncPage(store: widget.store),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                  ],
                  ListTile(
                    key: const ValueKey('settings-backup-entry'),
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('备份与恢复'),
                    subtitle: const Text('导出完整 JSON 配置、恢复追剧记录与网络调度设置'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => BackupSettingsPage(
                          store: widget.store,
                          repository: widget.repository,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 6. 隐私与安全
              SettingsGroupCard(
                title: '隐私与安全',
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

              // 7. 关于与支持
              SettingsGroupCard(
                title: '关于与支持',
                icon: Icons.info_outline_rounded,
                children: [
                  ListTile(
                    key: const ValueKey('settings-app-intro-entry'),
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('应用说明'),
                    subtitle: const Text('核心功能特性、架构说明与使用技巧'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const AppIntroPage(),
                      ),
                    ),
                  ),
                  ListTile(
                    key: const ValueKey('settings-contact-entry'),
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('联系方式'),
                    subtitle: const Text('官方邮箱 · GitHub 开源 · Telegram 交流'),
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
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: const Text('播放诊断日记'),
                    subtitle: const Text('查看原生解码、流媒体握手与解密运行轨迹'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => DiaryService.showDiaryDialog(context),
                  ),
                  ListTile(
                    key: const ValueKey('settings-about-entry'),
                    leading: const Icon(Icons.verified_outlined),
                    title: const Text('关于 $appName'),
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
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
