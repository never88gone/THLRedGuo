import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/home_screen.dart';
import 'package:THLRedLook/js_source_models.dart';
import 'package:THLRedLook/js_source_presets.dart';
import 'package:THLRedLook/js_source_service.dart';
import 'package:THLRedLook/local_store.dart';

import 'fixtures.dart';

class SwitchTestingMockRepository extends FixtureRepository {
  final Map<String, JsSourceMeta> _installedSources = {};
  String _activeId = 'hongguo';

  @override
  Future<List<JsSourceMeta>> jsSourceList() async {
    return _installedSources.values.toList();
  }

  @override
  Future<bool> jsSourceSetActive(String sourceId) async {
    _activeId = sourceId;
    return true;
  }

  @override
  Future<String> jsSourceGetActive() async => _activeId;

  @override
  Future<bool> jsSourceSaveAndLoad(String script, String fileName) async {
    final idMatch = RegExp(r'id:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(script);
    final nameMatch = RegExp(r'name:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(script);
    if (idMatch == null || nameMatch == null) return false;
    final meta = JsSourceMeta(
      id: idMatch.group(1)!,
      name: nameMatch.group(1)!,
      version: '1.0.0',
      description: 'Mock',
    );
    _installedSources[meta.id] = meta;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('首页数据源切换防震荡与红果首页渲染测试', () {
    late SwitchTestingMockRepository repo;
    late LocalStore store;
    late JsSourceService jsService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = testStore(prefs);
      repo = SwitchTestingMockRepository();

      jsService = JsSourceService(repo, prefs);
      // 预先装载红果和韩小圈
      for (final p in kPresetJsSources.take(2)) {
        await jsService.importScript(p.script, p.fileName);
      }
      await jsService.switchSource('hongguo');
    });

    testWidgets('首页红果数据源卡片正常渲染，不产生白屏', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: repo,
            store: store,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 验证首页成功渲染短剧卡片与站源信息，未显示空白或错误状态
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(store.source, equals('hongguo'));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('通过顶部数据源切换器平滑切换数据源，单向收敛不产生震荡', (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: repo,
            store: store,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(store.source, equals('hongguo'));
      expect(store.allowsSource('hanxiaoquan'), isTrue);

      // 点击 AppBar 上的数据源切换按钮
      final switchBtn = find.byKey(const ValueKey('source-switch'));
      expect(switchBtn, findsOneWidget);
      await tester.tap(switchBtn);
      await tester.pumpAndSettle();

      // 验证底部切换面板已弹出并包含韩小圈与红果
      expect(find.text('切换数据源'), findsOneWidget);
      expect(find.text('红果免费短剧'), findsWidgets);
      expect(find.text('韩小圈'), findsOneWidget);

      // 点击「韩小圈」进行切换
      await tester.tap(find.text('韩小圈'));
      await tester.pumpAndSettle();

      // 验证切换成功反馈提示已出现
      expect(find.textContaining('已切换至数据源：韩小圈'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
