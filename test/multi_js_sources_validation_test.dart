import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/js_source_models.dart';
import 'package:THLRedLook/js_source_presets.dart';
import 'package:THLRedLook/js_source_service.dart';
import 'package:THLRedLook/pages/settings/js_sources_page.dart';

import 'fixtures.dart';

/// 具有严格 JS 脚本校验能力的 Mock 仓储，模拟原生沙箱加载行为
class ValidatingMockJsRepository extends FixtureRepository {
  final Map<String, JsSourceMeta> _installedSources = {};
  String _activeId = '';

  static final RegExp _idRegex = RegExp(r'^[a-zA-Z0-9_\-\.]+$');

  /// 模拟原生沙箱的静态语法与元数据校验
  JsSourceMeta? _validateAndExtractMeta(String script) {
    if (script.trim().isEmpty) return null;
    if (script.contains('invalid syntax')) return null;

    final idMatch = RegExp(r'id:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(script);
    final nameMatch = RegExp(r'name:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(script);
    final versionMatch = RegExp(r'version:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(script);

    if (idMatch == null || nameMatch == null) return null;
    final id = idMatch.group(1)!.trim();
    final name = nameMatch.group(1)!.trim();
    if (id.isEmpty || name.isEmpty || !_idRegex.hasMatch(id)) return null;

    // 检查核心方法 (CatPawOpen Spider 至少需要 category 或 detail 之一)
    final hasCategory = script.contains('category');
    final hasDetail = script.contains('detail');
    if (!hasCategory && !hasDetail) return null;

    final List<String> features = [];
    if (script.contains('search')) features.add('search');
    if (script.contains('home') || script.contains('categories')) features.add('categories');
    if (script.contains('play')) features.add('playback');

    return JsSourceMeta(
      id: id,
      name: name,
      version: versionMatch?.group(1) ?? '1.0.0',
      description: 'Mock 验证源',
      features: features.isNotEmpty ? features : ['search', 'categories'],
    );
  }

  @override
  Future<List<JsSourceMeta>> jsSourceList() async {
    return _installedSources.values.toList();
  }

  @override
  Future<bool> jsSourceSetActive(String sourceId) async {
    if (!_installedSources.containsKey(sourceId)) return false;
    _activeId = sourceId;
    return true;
  }

  @override
  Future<String> jsSourceGetActive() async => _activeId;

  @override
  Future<bool> jsSourceSaveAndLoad(String script, String fileName) async {
    final meta = _validateAndExtractMeta(script);
    if (meta == null) {
      return false;
    }
    _installedSources[meta.id] = meta;
    if (_activeId.isEmpty) {
      _activeId = meta.id;
    }
    return true;
  }

  @override
  Future<bool> jsSourceRemove(String sourceId) async {
    if (!_installedSources.containsKey(sourceId)) return false;
    _installedSources.remove(sourceId);
    if (_activeId == sourceId) {
      _activeId = _installedSources.keys.isNotEmpty ? _installedSources.keys.first : '';
    }
    return true;
  }

  @override
  Future<int> jsSourceScan() async => _installedSources.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('多数据源 JS 插件规范与元数据完备性验证', () {
    test('预设插件库覆盖 5 大主流短剧/影视数据源且无重复标识', () {
      expect(kPresetJsSources.length, greaterThanOrEqualTo(5));

      final ids = <String>{};
      final fileNames = <String>{};

      for (final preset in kPresetJsSources) {
        expect(preset.fileName.endsWith('.js'), isTrue);
        expect(fileNames.add(preset.fileName), isTrue,
            reason: '文件名不能重复: ${preset.fileName}');

        // 验证各源脚本必须包含严格的 meta 定义与 CatPawOpen 标准接口
        expect(preset.script, contains('const meta = {'));
        expect(preset.script, contains('home'));
        expect(preset.script, contains('category'));
        expect(preset.script, contains('detail'));
        expect(preset.script, contains('play'));
        expect(preset.script, contains('var spider = {'));

        final idMatch = RegExp(r'id:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(preset.script);
        expect(idMatch, isNotNull, reason: '${preset.fileName} 缺少 meta.id');
        final id = idMatch!.group(1)!;
        expect(RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(id), isTrue,
            reason: '$id 包含非法字符');
        expect(ids.add(id), isTrue, reason: '数据源 ID 不能重复: $id');
      }

      // 验证包含预设的核心源
      expect(ids, containsAll(['hongguo']));
    });
  });

  group('JsSourceService 多数据源导入验证与拦截逻辑', () {
    test('导入非法/残缺插件应被严格拦截拒装', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = ValidatingMockJsRepository();
      final service = JsSourceService(repo);
      await service.initialize();

      // 1. 空脚本
      expect(await service.importScript('', 'empty.js'), isFalse);

      // 2. 语法错误脚本
      expect(await service.importScript('const a = invalid syntax;', 'syntax_err.js'), isFalse);

      // 3. 缺少 meta 的脚本
      expect(await service.importScript('function foo() { return 1; }', 'no_meta.js'), isFalse);

      // 4. meta.id 包含非法字符的脚本
      expect(
        await service.importScript(
          'const meta = { id: "bad id with spaces!", name: "测试" };\nfunction category() {}',
          'bad_id.js',
        ),
        isFalse,
      );

      // 5. 缺少必须核心方法的脚本 (既无 category 也无 detail)
      expect(
        await service.importScript(
          'const meta = { id: "valid_id", name: "有效名称" };',
          'no_methods.js',
        ),
        isFalse,
      );

      // 验证未装载任何非法插件
      expect(service.sources.isEmpty, isTrue);
    });

    test('批量导入 5 个数据源全部成功并通过协议验证', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = ValidatingMockJsRepository();
      final service = JsSourceService(repo);
      await service.initialize();

      final importedCount = await importPresetSources(service);
      expect(importedCount, equals(kPresetJsSources.length));
      expect(service.sources.length, equals(kPresetJsSources.length));

      // 验证默认激活第一个源
      expect(service.activeSourceId, equals('hongguo'));
      expect(service.activeSource?.name, equals('红果免费短剧'));

      // 验证每个已装载源的元数据完整性
      for (final preset in kPresetJsSources) {
        final found = service.sources.firstWhere((s) => s.name == preset.name);
        expect(found.id.isNotEmpty, isTrue);
        expect(found.features, isNotEmpty);
      }
    });

    test('在多个数据源之间动态平滑切换与持久化偏好', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = ValidatingMockJsRepository();
      final service = JsSourceService(repo);
      await service.initialize();

      await importPresetSources(service);
      expect(service.sources.length, greaterThanOrEqualTo(5));

      final targetSources = ['hanxiaoquan', 'yeguo', 'huangdou', 'dsd', 'hongguo'];
      final prefs = await SharedPreferences.getInstance();

      for (final targetId in targetSources) {
        var notified = false;
        void listener() => notified = true;
        service.addListener(listener);

        final ok = await service.switchSource(targetId);
        service.removeListener(listener);

        expect(ok, isTrue);
        expect(notified, isTrue);
        expect(service.activeSourceId, equals(targetId));
        expect(await repo.jsSourceGetActive(), equals(targetId));
        expect(prefs.getString('active_js_source_id'), equals(targetId));
      }

      // 切换至不存在的源应被拒绝且保持当前活跃源不变
      final fail = await service.switchSource('non_existent_source');
      expect(fail, isFalse);
      expect(service.activeSourceId, equals('hongguo'));
    });
  });

  group('UI 层多数据源展示与交互验证', () {
    testWidgets('JsSourcesPage 完整呈现所有已导入数据源卡片并支持一键切换', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = ValidatingMockJsRepository();
      final store = testStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      await store.activateZhenguojian();

      final service = JsSourceService(repo);
      await service.initialize();
      await importPresetSources(service);

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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
      await tester.pumpAndSettle();

      // 验证 5 个数据源全部展示在列表中
      expect(find.text('红果免费短剧'), findsOneWidget);
      expect(find.text('韩小圈'), findsOneWidget);
      expect(find.text('野果短剧'), findsOneWidget);
      expect(find.text('黄豆剧场'), findsOneWidget);
      expect(find.text('大时代短剧'), findsOneWidget);

      // 验证当前只有 1 个源标记为“当前激活”
      expect(find.text('当前激活'), findsOneWidget);

      // 查找野果短剧并点击切换激活
      final yeguoFinder = find.widgetWithText(Card, '野果短剧');
      expect(yeguoFinder, findsOneWidget);

      // 在野果短剧卡片中找到“激活”按钮并点击
      final yeguoActivateBtn = find.descendant(
        of: yeguoFinder,
        matching: find.widgetWithText(TextButton, '激活'),
      );
      expect(yeguoActivateBtn, findsOneWidget);

      await tester.tap(yeguoActivateBtn);
      await tester.pumpAndSettle();

      // 验证当前激活源已切换至野果短剧
      expect(service.activeSourceId, equals('yeguo'));
      expect(find.text('当前激活'), findsOneWidget);

      // 查找大时代短剧并点击切换激活
      final dsdFinder = find.widgetWithText(Card, '大时代短剧');
      expect(dsdFinder, findsOneWidget);

      final dsdActivateBtn = find.descendant(
        of: dsdFinder,
        matching: find.widgetWithText(TextButton, '激活'),
      );
      expect(dsdActivateBtn, findsOneWidget);

      await tester.tap(dsdActivateBtn);
      await tester.pumpAndSettle();

      // 验证当前激活源已切换至大时代短剧
      expect(service.activeSourceId, equals('dsd'));
    });
  });
}
