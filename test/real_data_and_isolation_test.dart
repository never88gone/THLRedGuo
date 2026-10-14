import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/catpaw_js_runtime.dart';
import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/js_source_presets.dart';
import 'package:THLRedLook/js_source_service.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });
  });

  group('数据源独立隔离性与真实数据验证', () {
    late AppRepository repository;
    late JsSourceService jsSourceService;

    setUp(() async {
      repository = NativeRepository();
      await repository.initialize();
      jsSourceService = JsSourceService(repository);
      await jsSourceService.initialize();
      await jsSourceService.clearAll();
    });

    test('1. 多数据源 ID 与命名空间隔离：每个源的短剧均严格带有 source: 前缀，绝不串联', () async {
      // 逐个分别导入 5 个预置源
      for (final preset in kPresetJsSources) {
        final ok = await importSinglePresetSource(jsSourceService, preset.id);
        expect(ok, isTrue);
      }
      expect(jsSourceService.sources.length, equals(5));

      // 验证各个源导出的分类与短剧 ID
      final Map<String, Set<String>> sourceDramaIds = {};

      for (final preset in kPresetJsSources) {
        final catalog = await repository.catalog(preset.id, page: 1);
        final ids = catalog.items.map((d) => d.id).toSet();
        for (final drama in catalog.items) {
          expect(drama.source, equals(preset.id), reason: '剧目所属 source 必须等于当前数据源 ID');
          expect(drama.id.startsWith('${preset.id}:'), isTrue, reason: '剧目 ID 必须以数据源前缀命名空间开头');
        }

        sourceDramaIds[preset.id] = ids;
      }

      // 验证真实有效源（红果、韩小圈）确实获取到了真实数据
      expect(sourceDramaIds['hongguo']!.isNotEmpty, isTrue);
      expect(sourceDramaIds['hanxiaoquan']!.isNotEmpty, isTrue);

      // 验证各数据源之间的短剧 ID 绝对无任何交集（隔离性 100%）
      final activeSources = sourceDramaIds.entries.where((e) => e.value.isNotEmpty).map((e) => e.key).toList();
      for (var i = 0; i < activeSources.length; i++) {
        for (var j = i + 1; j < activeSources.length; j++) {
          final srcA = activeSources[i];
          final srcB = activeSources[j];
          final intersection = sourceDramaIds[srcA]!.intersection(sourceDramaIds[srcB]!);
          expect(
            intersection.isEmpty,
            isTrue,
            reason: '数据源 $srcA 与 $srcB 之间绝不应存在相同 ID 的短剧 (发现重叠: $intersection)',
          );
        }
      }
    });

    test('2. 真实网络接口数据连通性验证：韩小圈 (jennyhow.com) 实时拉取真实韩剧目录', () async {
      final preset = findPresetSource('hanxiaoquan')!;
      final rt = CatPawJsRuntime();
      await rt.init(preset.script);

      // 请求真实分类
      final home = await rt.home();
      expect(home.classes, isNotEmpty);
      expect(home.classes.first['type_name'], contains('韩剧'));

      // 实际发起网络请求到 jennyhow.com
      final catResult = await rt.category('1', 1);
      expect(catResult.list, isNotEmpty);

      final firstDrama = catResult.list.first;
      expect(firstDrama['vod_name'], isNotEmpty);
      expect(firstDrama['vod_id'], isNotEmpty);

      rt.dispose();
    });

    test('3. 真实网络接口数据连通性验证：红果 (hongguoduanju.com) 官方直链与真实流媒体', () async {
      final preset = findPresetSource('hongguo')!;
      final rt = CatPawJsRuntime();
      await rt.init(preset.script);

      // 验证 home 分类返回官方四大频道
      final home = await rt.home();
      expect(home.classes.length, greaterThanOrEqualTo(4));

      // 验证 category 具备有效剧目
      final catResult = await rt.category('real-drama', 1);
      expect(catResult.list, isNotEmpty);

      // 验证 play 返回支持起播的直链 URL 与安全 Header
      final playResult = await rt.play('default', '7686713195246930968');
      expect(playResult.url, isNotEmpty);
      expect(playResult.url.startsWith('http'), isTrue);
      expect(playResult.header['User-Agent'], isNotEmpty);

      rt.dispose();
    });

    test('4. 缓存隔离性验证：不同数据源的 catalog 缓存互不干扰', () async {
      await importSinglePresetSource(jsSourceService, 'hongguo');
      await importSinglePresetSource(jsSourceService, 'hanxiaoquan');

      await repository.catalog('hongguo', page: 1);
      await repository.catalog('hanxiaoquan', page: 1);

      final hgCached = await repository.cached('hongguo');
      final hxqCached = await repository.cached('hanxiaoquan');

      expect(hgCached.items.isNotEmpty, isTrue);
      expect(hxqCached.items.isNotEmpty, isTrue);

      expect(hgCached.items.first.source, equals('hongguo'));
      expect(hxqCached.items.first.source, equals('hanxiaoquan'));
      expect(hgCached.items.first.id, isNot(equals(hxqCached.items.first.id)));
    });
  });
}
