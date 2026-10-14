import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/source_switcher_sheet.dart';
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

  testWidgets('SourceSwitcherSheet shows sources and allows switching', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(SourceSite.resetRuntimeActivation);

    final store = await createStore();
    // 激活真果鉴并解锁所有站源
    await store.activateZhenguojian();
    expect(store.sourcesUnlocked, isTrue);
    expect(store.sources.length, 11);

    SourceSite? selectedSource;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showSourceSwitcherSheet(
                  context,
                  store: store,
                  currentSource: SourceSite.hongguo,
                  onSelect: (site) {
                    selectedSource = site;
                    store.setSource(site.id);
                  },
                );
              },
              child: const Text('打开切换数据源'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 点击打开底部面板
    await tester.tap(find.text('打开切换数据源'));
    await tester.pumpAndSettle();

    expect(find.text('切换数据源'), findsOneWidget);
    expect(find.text('红果'), findsOneWidget);
    expect(find.text('韩小圈'), findsOneWidget);
    expect(find.text('鬼片'), findsOneWidget);
    expect(find.text('青空'), findsOneWidget);
    expect(find.text('黄豆'), findsOneWidget);
    expect(find.text('剧果'), findsOneWidget);
    expect(find.text('野果'), findsOneWidget);
    expect(find.text('帝果'), findsOneWidget);

    // 点击切换至「韩小圈」
    await tester.tap(find.text('韩小圈'));
    await tester.pumpAndSettle();

    expect(selectedSource?.id, 'hanxiaoquan');
    expect(find.text('已切换至数据源：韩小圈'), findsOneWidget);
  });
}
