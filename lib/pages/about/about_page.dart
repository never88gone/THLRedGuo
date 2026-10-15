import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app_colors.dart';
import '../../app_layout.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../../source_gate_taps.dart';
import '../../source_switcher_sheet.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.store});

  final LocalStore store;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final _tapGate = RepeatTapGate(threshold: 10);
  DateTime? _lastTapTime;
  String _versionDisplay = 'v$appVersion';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final version = info.version.isNotEmpty ? info.version : appVersion;
      final build = info.buildNumber.isNotEmpty ? ' (Build ${info.buildNumber})' : '';
      setState(() {
        _versionDisplay = 'v$version$build';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _versionDisplay = 'v${AppLayout.versionOf(context)}';
      });
    }
  }

  Future<void> _onVersionTapped() async {
    if (widget.store.isZhenguojianActivated) {
      showSourceSwitcherSheet(
        context,
        store: widget.store,
        onSelect: (site) {
          unawaited(widget.store.setSource(site.id));
          if (mounted) setState(() {});
        },
      );
      return;
    }

    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!) > const Duration(seconds: 3)) {
      _tapGate.reset();
    }
    _lastTapTime = now;

    final triggered = _tapGate.register('app_version');
    if (triggered) {
      if (!kIsWeb) {
        HapticFeedback.heavyImpact();
      }
      await widget.store.activateZhenguojian();
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 糖葫芦Haw已解锁全部数据源！'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      showSourceSwitcherSheet(
        context,
        store: widget.store,
        onSelect: (site) {
          unawaited(widget.store.setSource(site.id));
        },
      );
    } else {
      final taps = _tapGate.taps;
      if (taps >= 5 && taps < 10) {
        if (!kIsWeb) {
          HapticFeedback.selectionClick();
        }
        final remaining = 10 - taps;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('再点击 $remaining 次开启全数据源'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 900),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final isActivated = widget.store.isZhenguojianActivated;
        final currentSource = SourceSite.byId(widget.store.source);

        return Scaffold(
          appBar: AppBar(
            title: const Text('关于'),
            centerTitle: true,
          ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.blackSubtle20,
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/branding/app_icon.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [AppColors.darkSurface, AppColors.hongguoRedDark],
                            ),
                          ),
                          child: const Icon(
                            Icons.play_circle_filled_rounded,
                            size: 48,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      appName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '全平台独立短剧与流媒体聚合',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.darkSurfaceHighest,
                    child: Icon(
                      Icons.verified_rounded,
                      color: isActivated ? AppColors.green : AppColors.hongguoRed,
                    ),
                  ),
                  title: const Text('应用版本'),
                  subtitle: Text(_versionDisplay),
                  onTap: _onVersionTapped,
                ),
              ),

              if (isActivated) ...[
                const SizedBox(height: 16),
                Card(
                  key: const ValueKey('about-zhenguojian-card'),
                  elevation: 0,
                  color: isDark ? AppColors.darkCard : AppColors.greyLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppColors.accentBorder40,
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.all_inclusive_rounded,
                              color: AppColors.hongguoRed,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '糖葫芦Haw · 数据源管理',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.hongguoRed,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '共 ${widget.store.sources.length} 个站源',
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.accentSubtle08,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppColors.hongguoRed, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '当前正在使用：${currentSource.name} (${currentSource.description})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '快速选择站源：',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final site in widget.store.sources)
                              ChoiceChip(
                                key: ValueKey('chip-${site.id}'),
                                label: Text(site.name),
                                selected: site.id == currentSource.id,
                                onSelected: (selected) {
                                  if (selected) {
                                    unawaited(widget.store.setSource(site.id));
                                    setState(() {});
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('已切换至数据源：${site.name}'),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                key: const ValueKey('about-open-source-switcher'),
                                icon: const Icon(Icons.swap_horiz_rounded),
                                label: const Text('打开完整切换数据源面板'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () {
                                  showSourceSwitcherSheet(
                                    context,
                                    store: widget.store,
                                    onSelect: (site) {
                                      unawaited(widget.store.setSource(site.id));
                                      setState(() {});
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.stars_rounded, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '核心特性',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureRow(
                        icon: Icons.offline_bolt_rounded,
                        title: '端侧闭环解析',
                        description: '站源请求、协议解析与播放完全在设备本地完成，无需云端中心服务。',
                      ),
                      const Divider(height: 20),
                      _buildFeatureRow(
                        icon: Icons.devices_rounded,
                        title: '全平台深度适配',
                        description: '覆盖 Android、iOS、macOS、Windows、Android TV 与 Apple tvOS。',
                      ),
                      const Divider(height: 20),
                      _buildFeatureRow(
                        icon: Icons.download_rounded,
                        title: '高速离线下载',
                        description: '多并发调度与断点续传引擎，支持离线零流量播放与全集无损合并。',
                      ),
                      const Divider(height: 20),
                      _buildFeatureRow(
                        icon: Icons.security_rounded,
                        title: '数据私密保护',
                        description: '观看历史与收藏仅存储于本地，支持九宫格手势锁与独立私密保险箱。',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                elevation: 0,
                color: isDark ? AppColors.darkCard : AppColors.greyLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Text(
                            '免责声明与致谢',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '本项目源码来自网上大名鼎鼎的鱼佬（原作者）。仅用于个人学习研究、打包测试与多端适配体验，不保证任何可用性，随时可能删库。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Copyright © 2026 $appName. All rights reserved.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  },
);
}

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: theme.textTheme.bodySmall?.color,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
