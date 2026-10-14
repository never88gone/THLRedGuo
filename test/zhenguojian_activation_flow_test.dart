import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/pages/about/about_page.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真果鉴激活全流程：解锁全部11个数据源、关于页切源后发现页实时刷新且支持多站源请求', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(SourceSite.resetRuntimeActivation);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = testStore(prefs);
    addTearDown(store.dispose);

    final repository = FixtureRepository();
    // 准备不同站源的测试短剧数据
    final dramaHongguo = const Drama(
      id: 'hongguo:101',
      source: 'hongguo',
      title: '红果测试剧',
      episodes: 10,
    );
    final dramaHanxiaoquan = const Drama(
      id: 'hanxiaoquan:202',
      source: 'hanxiaoquan',
      title: '韩小圈测试剧',
      episodes: 16,
    );
    final dramaHuangdou = const Drama(
      id: 'huangdou:303',
      source: 'huangdou',
      title: '黄豆测试剧',
      episodes: 80,
    );

    repository.cachedPages['hongguo'] = CatalogPage([dramaHongguo]);
    repository.cachedPages['hanxiaoquan'] = CatalogPage([dramaHanxiaoquan]);
    repository.cachedPages['huangdou'] = CatalogPage([dramaHuangdou]);
    repository.catalogPages['hongguo'] = CatalogPage([dramaHongguo]);
    repository.catalogPages['hanxiaoquan'] = CatalogPage([dramaHanxiaoquan]);
    repository.catalogPages['huangdou'] = CatalogPage([dramaHuangdou]);

    // 1. 未激活前，只有 4 个基础主站源
    expect(store.isZhenguojianActivated, isFalse);
    expect(store.sources.length, 4);
    expect(store.sources.first.id, 'hongguo');

    // 2. 在关于页面轻触 10 次激活真果鉴
    await tester.pumpWidget(
      MaterialApp(
        home: AboutPage(store: store),
      ),
    );
    await tester.pump();

    final versionTile = find.text('应用版本');
    expect(versionTile, findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.tap(versionTile);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // 验证：已激活并解锁全部 11 个数据源！
    expect(store.isZhenguojianActivated, isTrue);
    expect(store.sources.length, 11);
    expect(find.text('🎉 糖葫芦果鉴已解锁全部数据源！'), findsOneWidget);

    // 验证切换面板中出现全部站源：红果、韩小圈、鬼片、青空、黄豆、剧果、野果、帝果
    expect(find.text('切换数据源'), findsOneWidget);
    expect(find.text('红果'), findsWidgets);
    expect(find.text('韩小圈'), findsWidgets);
    expect(find.text('青空'), findsWidgets);
    expect(find.text('黄豆'), findsWidgets);
    expect(find.text('剧果'), findsWidgets);
    expect(find.text('野果'), findsWidgets);
    expect(find.text('帝果'), findsWidgets);

    // 3. 在切换面板中选择「韩小圈」
    await tester.tap(find.text('韩小圈').last);
    await tester.pumpAndSettle();
    expect(store.source, 'hanxiaoquan');

    // 4. 加载 HomeScreen，验证发现页当前选中的数据源为「韩小圈」且内容已刷新为韩小圈剧集
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repository: repository,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 验证发现页 AppBar 标题为韩小圈
    expect(find.text('韩小圈'), findsWidgets);
    expect(find.text('韩小圈测试剧'), findsOneWidget);

    // 5. 模拟在关于页再次切换为「黄豆」，验证 HomeScreen 会实时感知并刷新为「黄豆」
    await store.setSource('huangdou');
    await tester.pumpAndSettle();

    expect(find.text('黄豆'), findsWidgets);
    expect(find.text('黄豆测试剧'), findsOneWidget);

    // 6. 验证其他站源的授权检查通过，不会抛出「当前版本不包含此站源」
    expect(() => store.allowsSource('huangdou'), returnsNormally);
    expect(store.allowsSource('huangdou'), isTrue);
    expect(store.allowsSource('hanxiaoquan'), isTrue);
    expect(store.allowsSource('dsd'), isTrue);
  });
}
