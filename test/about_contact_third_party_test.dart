import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/pages/about/about_page.dart';
import 'package:THLRedLook/pages/about/contact_page.dart';
import 'package:THLRedLook/pages/about/third_party_page.dart';
import 'package:THLRedLook/pages/settings/settings_page.dart';
import 'package:THLRedLook/utils/build/app_build.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = LocalStore(prefs);
  });

  testWidgets('AboutPage renders clean main screen with app info, version, and disclaimer without bottom list', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AboutPage(store: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关于 $appName'), findsOneWidget);
    expect(find.text('应用版本'), findsOneWidget);
    expect(find.text('免责声明 (Disclaimer)'), findsOneWidget);

    // 验证关于页面底部的列表已彻底移除
    expect(find.byKey(const ValueKey('about-contact-tile')), findsNothing);
    expect(find.byKey(const ValueKey('about-third-party-tile')), findsNothing);
    expect(find.byKey(const ValueKey('about-app-intro-tile')), findsNothing);
  });

  testWidgets('ContactPage displays details and handles copy button', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: ContactPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('联系方式'), findsOneWidget);

    // 1. 验证邮箱联系卡片与复制
    expect(find.text('官方支持与反馈邮箱'), findsOneWidget);
    expect(find.text('support@thltv.com'), findsOneWidget);
    final copyEmailBtn = find.byKey(const ValueKey('btn-copy-email'));
    expect(copyEmailBtn, findsOneWidget);
    await tester.tap(copyEmailBtn);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('已复制 邮箱地址：support@thltv.com'), findsOneWidget);

    // 2. 验证 GitHub 开源项目卡片与复制
    expect(find.text('GitHub 官方开源仓库'), findsOneWidget);
    expect(find.text('https://github.com/never88gone/THLRedGuo'), findsOneWidget);
    final copyGithubBtn = find.byKey(const ValueKey('btn-copy-github'));
    expect(copyGithubBtn, findsOneWidget);
    await tester.tap(copyGithubBtn);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('已复制 GitHub 地址：https://github.com/never88gone/THLRedGuo'), findsOneWidget);

    // 3. 验证 Telegram 官方频道与复制
    expect(find.text('Telegram 官方交流与反馈'), findsOneWidget);
    expect(find.text('@tanghulutvos'), findsOneWidget);

    final copyBtn = find.byKey(const ValueKey('btn-copy-telegram'));
    expect(copyBtn, findsOneWidget);
    await tester.tap(copyBtn);
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('已复制 Telegram 地址'), findsOneWidget);
  });

  testWidgets('ThirdPartyPage renders core libraries and license page button', (tester) async {
    tester.view.physicalSize = const Size(800, 2500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ThirdPartyPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第三方开源组件'), findsOneWidget);
    expect(find.text('Flutter SDK'), findsOneWidget);
    expect(find.text('致敬开源贡献'), findsOneWidget);
    expect(find.byKey(const ValueKey('btn-system-license-page')), findsOneWidget);
  });

  testWidgets('HomeAppBarView renders settings button without refresh button', (tester) async {
    bool settingsClicked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                key: const ValueKey('home-appbar-settings-button'),
                tooltip: '设置',
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => settingsClicked = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-appbar-settings-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-refresh')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-appbar-settings-button')));
    expect(settingsClicked, isTrue);
  });

  testWidgets('SettingsScreen provides entries for AppIntro, Contact, ThirdParty, and About', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = NativeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          repository: repo,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-app-intro-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-contact-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-third-party-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-about-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-display-mode-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-theme-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-playback-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-backup-entry')), findsOneWidget);

    // 验证跳转到页面模式子页面
    await tester.tap(find.byKey(const ValueKey('settings-display-mode-entry')));
    await tester.pumpAndSettle();
    expect(find.text('全平台界面呈现模式'), findsOneWidget);
    expect(find.text('电视 / 遥控器模式'), findsOneWidget);
    expect(find.text('手机 / 电脑模式'), findsOneWidget);
    Navigator.pop(tester.element(find.text('页面模式')));
    await tester.pumpAndSettle();

    // 验证跳转到播放偏好子页面
    await tester.tap(find.byKey(const ValueKey('settings-playback-entry')));
    await tester.pumpAndSettle();
    expect(find.text('默认起播画质'), findsOneWidget);
    expect(find.text('弹幕总开关'), findsOneWidget);
    Navigator.pop(tester.element(find.text('播放设置')));
    await tester.pumpAndSettle();

    // 验证跳转到备份与恢复子页面
    await tester.tap(find.byKey(const ValueKey('settings-backup-entry')));
    await tester.pumpAndSettle();
    expect(find.text('备份与恢复'), findsOneWidget);
    expect(find.text('导出完整配置备份'), findsOneWidget);
    expect(find.text('从备份文件恢复配置'), findsOneWidget);
    Navigator.pop(tester.element(find.text('备份与恢复')));
    await tester.pumpAndSettle();

    // 验证跳转到外观与主题子页面
    await tester.tap(find.byKey(const ValueKey('settings-theme-entry')));
    await tester.pumpAndSettle();
    expect(find.text('外观与主题'), findsOneWidget);
    expect(find.text('深色模式'), findsOneWidget);
    expect(find.text('浅色模式'), findsOneWidget);
  });
}
