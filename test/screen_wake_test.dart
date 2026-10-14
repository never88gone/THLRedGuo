import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/pages/settings/settings_page.dart';
import 'package:THLRedLook/resource_settings_screen.dart';
import 'package:THLRedLook/utils/screen/screen_wake_controller.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> createStore() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return LocalStore(prefs);
  }

  group('屏幕常亮与禁止锁屏功能测试', () {
    test('ScreenWakeController 状态同步与切回前台恢复', () async {
      final controller = ScreenWakeController.instance;

      await controller.sync(true);
      expect(controller.isWakeLocked, isTrue);

      await controller.sync(false);
      expect(controller.isWakeLocked, isFalse);

      await controller.handleAppResume(true);
      expect(controller.isWakeLocked, isTrue);

      await controller.sync(false);
    });

    test('LocalStore keepScreenOn 默认状态、切换与备份导出恢复', () async {
      final store = await createStore();
      addTearDown(store.dispose);

      // 默认不常亮
      expect(store.keepScreenOn, isFalse);

      // 开启常亮
      await store.setKeepScreenOn(true);
      expect(store.keepScreenOn, isTrue);

      // 重新实例化读取
      final reopened = LocalStore(store.preferences);
      addTearDown(reopened.dispose);
      expect(reopened.keepScreenOn, isTrue);

      // 导出备份测试
      final backupJson = await store.exportBackup();
      final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;
      expect(backupMap['keepScreenOn'], isTrue);

      // 关闭后通过备份恢复
      await store.setKeepScreenOn(false);
      expect(store.keepScreenOn, isFalse);

      await store.importBackup(backupJson);
      expect(store.keepScreenOn, isTrue);
    });

    testWidgets('SettingsScreen 渲染并切换“禁止自动锁屏”开关', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final store = await createStore();
      addTearDown(store.dispose);
      final repository = FixtureRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            repository: repository,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 检查标题与描述
      expect(find.text('禁止自动锁屏'), findsOneWidget);
      expect(find.text('保持屏幕常亮，防止离线下载与挂机时设备自动息屏休眠'), findsOneWidget);

      // 找到对应的 Switch
      final switchFinder = find.widgetWithText(SwitchListTile, '禁止自动锁屏');
      expect(switchFinder, findsOneWidget);

      // 点击切换开关
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(store.keepScreenOn, isTrue);

      // 再次点击关闭
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(store.keepScreenOn, isFalse);
    });

    testWidgets('DownloadPreferencesScreen 渲染并联动切换“禁止自动锁屏”', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final store = await createStore();
      addTearDown(store.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: DownloadPreferencesScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();

      // 检查下载偏好中的开关
      final switchFinder = find.widgetWithText(SwitchListTile, '禁止自动锁屏');
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(store.keepScreenOn, isTrue);
    });
  });
}
