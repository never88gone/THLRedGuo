import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/utils/sources/source_gate_taps.dart';
import 'package:THLRedLook/views/sources/source_switcher_sheet.dart';

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
              // 2. 版本号卡片
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

              const SizedBox(height: 16),

              // 3. 免责说明
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
                          const Icon(Icons.gavel_rounded, size: 20, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Text(
                            '免责声明 (Disclaimer)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '1. 本软件仅供移动端与大屏端跨平台编程技术学习、个人研究及非商业测试使用；\n'
                        '2. 本软件为纯本地客户端工具，开发者不提供、不存储、不修改任何网络音视频内容，所有媒体数据均来源于网络公开接口；\n'
                        '3. 媒体内容及相关版权均归原版权方所有，请自觉支持正版内容；\n'
                        '4. 使用者因个人使用行为产生的一切法律责任及版权纠纷均由使用者自行承担，与软件开发者无关。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.6,
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
}
