import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/js_source_models.dart';
import 'package:THLRedLook/js_source_service.dart';
import 'package:THLRedLook/pages/settings/js_sources_page.dart';

import 'fixtures.dart';

class MockJsRepository extends FixtureRepository {
  final List<JsSourceMeta> _mockSources = [
    const JsSourceMeta(
      id: 'hongguo',
      name: '红果免费短剧',
      version: '1.0.1',
      description: '官方首发短剧源',
      features: ['search', 'suggestions', 'categories'],
    ),
    const JsSourceMeta(
      id: 'hanxiaoquan',
      name: '韩小圈',
      version: '1.0.1',
      description: '韩剧精选资源',
      features: ['search', 'categories'],
    ),
  ];

  String _activeId = 'hongguo';

  @override
  Future<List<JsSourceMeta>> jsSourceList() async => List.of(_mockSources);

  @override
  Future<bool> jsSourceSetActive(String sourceId) async {
    _activeId = sourceId;
    return true;
  }

  @override
  Future<String> jsSourceGetActive() async => _activeId;

  @override
  Future<bool> jsSourceSaveAndLoad(String script, String fileName) async {
    return true;
  }

  @override
  Future<int> jsSourceScan() async => _mockSources.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JsSourceMeta 序列化与反序列化验证', () {
    const meta = JsSourceMeta(
      id: 'test_src',
      name: '测试数据源',
      version: '1.2.3',
      description: '用于单测的描述',
      author: 'Tester',
      features: ['search', 'danmaku'],
    );

    final jsonMap = meta.toJson();
    expect(jsonMap['id'], 'test_src');
    expect(jsonMap['name'], '测试数据源');
    expect(jsonMap['version'], '1.2.3');

    final parsed = JsSourceMeta.fromJson(jsonMap);
    expect(parsed.id, meta.id);
    expect(parsed.name, meta.name);
    expect(parsed.version, meta.version);
    expect(parsed.features, ['search', 'danmaku']);
    expect(parsed, equals(meta));
  });

  test('JsSourceService 能够切换数据源', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = MockJsRepository();
    final service = JsSourceService(repo);

    await service.initialize();
    expect(service.sources.length, 2);
    expect(service.activeSourceId, 'hongguo');
    expect(service.activeSource?.name, '红果免费短剧');

    // 切换至韩小圈
    final switched = await service.switchSource('hanxiaoquan');
    expect(switched, isTrue);
    expect(service.activeSourceId, 'hanxiaoquan');
    expect(service.activeSource?.name, '韩小圈');
    expect(await repo.jsSourceGetActive(), 'hanxiaoquan');
  });

  testWidgets('JsSourcesPage 正确呈现 JS 数据源列表并支持激活切换', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = MockJsRepository();
    final store = testStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await store.activateZhenguojian();

    final service = JsSourceService(repo);
    await service.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JsSourcesPage(
            repository: repo,
            store: store,
            service: service,
          ),
        ),
      ),
    );
    await tester.pump();

    // 验证页面包含标题和架构说明
    expect(find.text('JS 数据源插件管理'), findsOneWidget);
    expect(find.text('原生独立沙箱引擎 (v1.0.1)'), findsOneWidget);

    // 验证列出了两个插件
    expect(find.text('红果免费短剧'), findsOneWidget);
    expect(find.text('韩小圈'), findsOneWidget);
    expect(find.text('当前激活'), findsOneWidget);

    // 点击“激活”韩小圈
    final activateBtn = find.widgetWithText(TextButton, '激活');
    expect(activateBtn, findsOneWidget);
    await tester.tap(activateBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 验证当前激活变为韩小圈
    expect(service.activeSourceId, 'hanxiaoquan');
  });
}
