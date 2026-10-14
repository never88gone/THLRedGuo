import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/pages/about/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalStore> createStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = testStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  testWidgets('AboutPage renders branding and features', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await createStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AboutPage(store: store),
      ),
    );
    await tester.pump();

    expect(find.text('关于'), findsOneWidget);
    expect(find.text('糖葫芦果鉴'), findsOneWidget);
    expect(find.text('应用版本'), findsOneWidget);
    expect(find.text('端侧闭环解析'), findsOneWidget);
    expect(find.text('免责声明与致谢'), findsOneWidget);
  });

  testWidgets('tapping app version 10 times activates Zhenguojian', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(SourceSite.resetRuntimeActivation);

    final store = await createStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AboutPage(store: store),
      ),
    );
    await tester.pump();

    final versionTile = find.text('应用版本');
    expect(versionTile, findsOneWidget);
    expect(find.text('连点激活'), findsNothing);

    // 点击 1 到 4 次，不会弹出提示
    for (var i = 0; i < 4; i++) {
      await tester.tap(versionTile);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    }

    // 点击第 5 次，出现提示："再点击 5 次开启全数据源"
    await tester.tap(versionTile);
    await tester.pump();
    expect(find.text('再点击 5 次开启全数据源'), findsOneWidget);

    // 点击第 6~9 次
    for (var i = 6; i <= 9; i++) {
      await tester.tap(versionTile);
      await tester.pump();
      expect(find.text('再点击 ${10 - i} 次开启全数据源'), findsOneWidget);
    }

    // 点击第 10 次，触发激活，弹出完成 SnackBar 并唤起切换数据源面板
    await tester.tap(versionTile);
    await tester.pumpAndSettle();

    expect(find.text('🎉 糖葫芦果鉴已解锁全部数据源！'), findsOneWidget);
    expect(find.text('切换数据源'), findsOneWidget);
    expect(find.text('红果'), findsWidgets);
    expect(find.text('韩小圈'), findsWidgets);
    expect(find.text('青空'), findsWidgets);

    // 点击选择底部面板中的韩小圈项关闭面板后，验证关于页面上常驻显示真果鉴管理卡片与站源 Chips
    await tester.tap(find.text('韩小圈').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('about-zhenguojian-card')), findsOneWidget);
    expect(find.text('糖葫芦果鉴 · 数据源管理'), findsOneWidget);
    expect(find.byKey(const ValueKey('chip-hanxiaoquan')), findsOneWidget);
    expect(find.byKey(const ValueKey('chip-hongguo')), findsOneWidget);
  });

  test('LocalStore persists Zhenguojian activation across restarts', () async {
    addTearDown(SourceSite.resetRuntimeActivation);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store1 = testStore(prefs);
    addTearDown(store1.dispose);

    expect(store1.isZhenguojianActivated, isFalse);
    expect(store1.sources.length, 4);

    await store1.activateZhenguojian();
    expect(store1.isZhenguojianActivated, isTrue);
    expect(store1.sources.length, 11);
    expect(store1.allowsSource('hanxiaoquan'), isTrue);
    expect(store1.allowsSource('guipian'), isTrue);
    expect(store1.allowsSource('huangdou'), isTrue);
    expect(store1.allowsSource('dsd'), isTrue);

    // 模拟应用重启，重新从持久化快照初始化 store
    SourceSite.resetRuntimeActivation();
    final store2 = testStore(prefs);
    addTearDown(store2.dispose);

    expect(store2.isZhenguojianActivated, isTrue);
    expect(store2.sources.length, 11);
    expect(store2.allowsSource('hanxiaoquan'), isTrue);
    expect(store2.allowsSource('sorani'), isTrue);
    expect(store2.allowsSource('huangdou'), isTrue);
    expect(store2.allowsSource('dsd'), isTrue);
  });
}

