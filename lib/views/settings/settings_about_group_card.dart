import 'package:flutter/material.dart';

import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/core/update/app_update_service.dart';
import 'package:THLRedLook/pages/about/about_page.dart';
import 'package:THLRedLook/pages/about/app_intro_page.dart';
import 'package:THLRedLook/pages/about/contact_page.dart';
import 'package:THLRedLook/pages/about/third_party_page.dart';
import 'package:THLRedLook/pages/settings/release_notes_page.dart';
import 'package:THLRedLook/utils/build/app_build.dart';
import 'package:THLRedLook/utils/diary/diary_service.dart';
import 'package:THLRedLook/views/settings/settings_group_view.dart';
import 'package:THLRedLook/views/update/app_update_dialog.dart';

/// 设置页“关于与支持”分组卡片组件
class SettingsAboutGroupCard extends StatelessWidget {
  const SettingsAboutGroupCard({
    super.key,
    required this.appVersion,
    required this.store,
  });

  final String appVersion;
  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    return SettingsGroupCard(
      title: '关于与支持',
      icon: Icons.info_outline_rounded,
      children: [
        if (AppUpdateService.isSupportedPlatform)
          ListTile(
            key: const ValueKey('settings-check-update-entry'),
            leading: const Icon(Icons.system_update_rounded),
            title: const Text('检查新版本'),
            subtitle: const Text('检测官方 GitHub 最新版本及各端安装包'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => triggerCheckUpdate(context),
          ),
        ListTile(
          key: const ValueKey('settings-release-notes-entry'),
          leading: const Icon(Icons.history_rounded),
          title: const Text('更新内容'),
          subtitle: const Text('版本历程 · 每次版本与功能的更新记录'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const ReleaseNotesPage(),
            ),
          ),
        ),
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
          subtitle: Text(appVersion),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AboutPage(store: store),
            ),
          ),
        ),
      ],
    );
  }
}
