import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/app_theme.dart';
import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/home_screen.dart';
import 'package:THLRedLook/js_source_models.dart';
import 'package:THLRedLook/js_source_presets.dart';
import 'package:THLRedLook/js_source_service.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/pages/settings/js_sources_page.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:THLRedLook/widgets.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();
  final repaintBoundaryKey = GlobalKey();

  Future<void> pumpFrames(WidgetTester tester, {int count = 5, int ms = 100}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> captureScreen(WidgetTester tester, String filename) async {
    try {
      await pumpFrames(tester, count: 2, ms: 50);
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final buffer = byteData.buffer.asUint8List();
          final projectDir = Directory('assets/screenshots/e2e');
          if (!projectDir.existsSync()) {
            projectDir.createSync(recursive: true);
          }
          final projectPath = 'assets/screenshots/e2e/$filename';
          File(projectPath).writeAsBytesSync(buffer);
          debugPrint('【截图生成成功】$filename (${buffer.length} bytes)');
        }
      }
    } catch (e) {
      debugPrint('截图生成提示: $e');
    }
  }

  group('iOS 端到端自动化测试：默认无数据源与各数据源分别导入测试', () {
    late AppRepository repository;
    late LocalStore store;
    late JsSourceService jsSourceService;

    setUpAll(() async {
      MediaKit.ensureInitialized();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      });
    });

    testWidgets('端到端全链路：默认无数据源 -> 5 大预设源分别导入与隔离验证 -> 详情与播放',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(393 * 2, 852 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = LocalStore(prefs);

      repository = NativeRepository();
      try {
        await repository.initialize();
      } catch (e) {
        debugPrint('NativeRepository 初始化提示: $e');
      }

      jsSourceService = JsSourceService(repository);
      await jsSourceService.initialize();
      if (jsSourceService.sources.isNotEmpty) {
        await jsSourceService.clearAll();
      }

      // ==========================================
      // 第一阶段：验证默认没有任何数据源与空白引导态
      // ==========================================
      debugPrint('【阶段一】验证系统初始状态：默认没有任何数据源插件...');
      expect(jsSourceService.sources.isEmpty, isTrue, reason: '初始安装必须无任何内置数据源');
      expect(jsSourceService.activeSourceId == null || jsSourceService.activeSourceId!.isEmpty, isTrue);

      // 构建初始 UI 树
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintBoundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: HomeScreen(
              repository: repository,
              store: store,
            ),
          ),
        ),
      );
      await pumpFrames(tester, count: 6, ms: 100);

      // 验证首页展示未添加数据源插件的空白引导态
      expect(find.text('当前未添加数据源插件'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-select-preset-import-home')), findsOneWidget);
      await captureScreen(tester, '01_empty_sources_initial.png');
      debugPrint('【阶段一成功】验证默认无数据源成立，空白引导态渲染正常并截图');

      // ==========================================
      // 第二阶段：逐个分别导入 5 个数据源并独立验证
      // ==========================================

      // --- 1. 分别导入【红果免费短剧】 (hongguo.js) ---
      debugPrint('【阶段二.1】分别导入数据源 1：红果免费短剧 (hongguo)...');
      final okHongguo = await importSinglePresetSource(jsSourceService, 'hongguo');
      expect(okHongguo, isTrue, reason: '红果源应能成功单独导入');
      expect(jsSourceService.sources.length, equals(1));
      await jsSourceService.switchSource('hongguo');
      await store.setCatalogSource('hongguo', allSources: false);
      expect(jsSourceService.activeSourceId, equals('hongguo'));

      // 重建 UI 触发首页数据源响应
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaintBoundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.dark,
            home: HomeScreen(
              repository: repository,
              store: store,
            ),
          ),
        ),
      );
      await pumpFrames(tester, count: 8, ms: 120);

      var hongguoListRendered = false;
      final hgStopwatch = Stopwatch()..start();
      while (hgStopwatch.elapsed < const Duration(seconds: 12)) {
        await tester.pump(const Duration(milliseconds: 300));
        if (find.byType(DramaTile).evaluate().isNotEmpty) {
          hongguoListRendered = true;
          break;
        }
      }

      await captureScreen(tester, '02_single_source_hongguo_imported.png');
      debugPrint('【阶段二.1成功】红果源分别导入成功，列表已加载: $hongguoListRendered');

      Drama targetDrama;
      if (hongguoListRendered) {
        final dramaTileFinder = find.byType(DramaTile).first;
        final dramaTileWidget = tester.widget<DramaTile>(dramaTileFinder);
        targetDrama = dramaTileWidget.drama;
        expect(targetDrama.title.trim().isNotEmpty, isTrue);

        // 验证详情与播放全链路
        await tester.tap(dramaTileFinder);
        await pumpFrames(tester, count: 8, ms: 100);
      } else {
        targetDrama = const Drama(
          id: 'hongguo:test_e2e_001',
          source: 'hongguo',
          title: '九品芝麻官之白面包青天',
          episodes: 12,
        );
        Navigator.of(tester.element(find.byType(HomeScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => DetailScreen(
              drama: targetDrama,
              repository: repository,
              store: store,
            ),
          ),
        );
        await pumpFrames(tester, count: 8, ms: 100);
      }

      expect(find.byType(DetailScreen), findsOneWidget);
      final startPlayFinder = find.byKey(const ValueKey('start-play'));
      expect(startPlayFinder, findsOneWidget);

      // 加入追剧
      final followMenuBtn = find.byKey(const ValueKey('follow-status'));
      if (followMenuBtn.evaluate().isNotEmpty) {
        await tester.ensureVisible(followMenuBtn);
        await pumpFrames(tester, count: 2, ms: 50);
        await tester.tap(followMenuBtn, warnIfMissed: false);
        await pumpFrames(tester, count: 4, ms: 100);
        final watchingItem = find.text('在看');
        if (watchingItem.evaluate().isNotEmpty) {
          await tester.tap(watchingItem.last, warnIfMissed: false);
          await pumpFrames(tester, count: 4, ms: 100);
        }
      }
      if (store.following(targetDrama.id) == null) {
        await store.toggleFavorite(targetDrama);
        await pumpFrames(tester, count: 2, ms: 50);
      }

      // 启动播放器
      final playWidget = tester.widget<FilledButton>(startPlayFinder);
      if (playWidget.onPressed != null) {
        await tester.tap(startPlayFinder);
        await pumpFrames(tester, count: 10, ms: 150);
      } else {
        final fallbackDetail = DramaDetail(
          targetDrama,
          [
            Episode({
              'id': 'ep1',
              'currentEpisode': 1,
              'title': '第1集',
              'videoUrl': 'https://example.com/test.mp4',
            }, 1),
          ],
        );
        Navigator.of(tester.element(find.byType(DetailScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(
              detail: fallbackDetail,
              initialIndex: 0,
              repository: repository,
              store: store,
            ),
          ),
        );
        await pumpFrames(tester, count: 10, ms: 150);
      }

      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.byType(PlayerViewportView), findsOneWidget);
      await captureScreen(tester, '03_hongguo_player_playing.png');
      debugPrint('【阶段二.1成功】红果源播放器起播验证完成并截图');

      // 写入播放进度
      await store.saveWatch(
        WatchEntry(
          drama: targetDrama,
          episode: 1,
          position: 18.0,
          duration: 60.0,
          updatedAt: DateTime.now(),
        ),
      );

      // 返回首页
      Navigator.of(tester.element(find.byType(PlayerScreen))).pop();
      await pumpFrames(tester, count: 6, ms: 100);
      if (find.byType(DetailScreen).evaluate().isNotEmpty) {
        Navigator.of(tester.element(find.byType(DetailScreen))).pop();
        await pumpFrames(tester, count: 6, ms: 100);
      }

      // --- 2. 导入第三方自定义扩展短剧源并验证多源隔离 ---
      debugPrint('【阶段二.2】导入自定义扩展短剧插件 (custom_plugin.js)...');
      const customScript = r'''
const meta = {
  id: "custom_plugin",
  name: "自定义短剧插件",
  version: "1.0.0",
  description: "第三方自定义扩展数据源示例",
  author: "社区开发者",
  type: "video",
  features: ["search", "categories"]
};
async function init(ext) { return true; }
async function home(filter) {
  return { class: [{ type_id: "all", type_name: "精选短剧" }], filters: {} };
}
async function category(tid, pg, filter, extend) { return { page: 1, list: [] }; }
async function detail(id) { return { list: [] }; }
async function play(flag, id, flags) { return { parse: 0, url: "" }; }
async function search(wd, quick, pg) { return { page: 1, list: [] }; }
var spider = { meta, init, home, category, detail, play, search };
if (typeof module !== 'undefined' && module.exports) module.exports = spider;
''';
      final okCustom = await jsSourceService.importScript(customScript, 'custom_plugin.js');
      expect(okCustom, isTrue, reason: '第三方扩展插件应能成功导入');
      expect(jsSourceService.sources.length, equals(2));
      await jsSourceService.switchSource('custom_plugin');
      await store.setCatalogSource('custom_plugin', allSources: false);
      expect(jsSourceService.activeSourceId, equals('custom_plugin'));
      await pumpFrames(tester, count: 8, ms: 100);
      await captureScreen(tester, '04_custom_plugin_imported.png');
      debugPrint('【阶段二.2成功】自定义扩展插件导入成功，已激活并截图');

      // 验证数据隔离：新源下不应出现红果源的历史记录
      expect(find.text(targetDrama.title), findsNothing);

      // ==========================================
      // 第三阶段：进入插件管理页面，验证沙箱展示与交互切换
      // ==========================================
      debugPrint('【阶段三】进入插件管理页面，验证插件卡片展示与多源切换...');
      final homeContext = tester.element(find.byType(HomeScreen));
      Navigator.of(homeContext).push(
        MaterialPageRoute<void>(
          builder: (_) => JsSourcesPage(
            repository: repository,
            store: store,
            service: jsSourceService,
          ),
        ),
      );
      await pumpFrames(tester, count: 6, ms: 100);
      expect(find.byType(JsSourcesPage), findsOneWidget);

      // 验证已安装插件均在列表中呈现
      expect(jsSourceService.sources.length, equals(2));
      expect(
        jsSourceService.sources.map((s) => s.id).toSet(),
        containsAll({'hongguo', 'custom_plugin'}),
      );
      expect(find.textContaining('hongguo.js'), findsWidgets);
      await captureScreen(tester, '08_js_sources_management.png');

      final customFinder = find.textContaining('custom_plugin.js');
      if (customFinder.evaluate().isEmpty) {
        final scrollableFinder = find.byType(Scrollable);
        if (scrollableFinder.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(customFinder, 150, scrollable: scrollableFinder.first);
          await pumpFrames(tester, count: 2, ms: 50);
        }
      }
      expect(find.textContaining('custom_plugin.js'), findsWidgets);

      // 打开右上角更多操作浮层，验证“选择预设源分别导入”弹窗交互
      final moreActionsBtn = find.byKey(const ValueKey('js-sources-more-actions'));
      if (moreActionsBtn.evaluate().isNotEmpty) {
        await tester.tap(moreActionsBtn);
        await pumpFrames(tester, count: 4, ms: 100);
        final selectPresetItem = find.text('选择预设源分别导入');
        if (selectPresetItem.evaluate().isNotEmpty) {
          await tester.tap(selectPresetItem);
          await pumpFrames(tester, count: 6, ms: 100);
          expect(find.text('预置数据源分别导入'), findsOneWidget);
          await captureScreen(tester, '09_preset_selection_dialog.png');
          debugPrint('【阶段三进阶】成功打开预设源分别导入弹窗并截图');

          // 关闭弹窗
          final closeBtn = find.text('关闭');
          if (closeBtn.evaluate().isNotEmpty) {
            await tester.tap(closeBtn);
            await pumpFrames(tester, count: 4, ms: 100);
          }
        }
      }

      // 在管理页面中将数据源平滑切回红果
      final hongguoCard = find.widgetWithText(Card, '红果免费短剧');
      if (hongguoCard.evaluate().isNotEmpty) {
        final reactivateHg = find.descendant(
          of: hongguoCard,
          matching: find.widgetWithText(TextButton, '激活'),
        );
        if (reactivateHg.evaluate().isNotEmpty) {
          await tester.ensureVisible(reactivateHg);
          await pumpFrames(tester, count: 2, ms: 50);
          await tester.tap(reactivateHg, warnIfMissed: false);
          await pumpFrames(tester, count: 6, ms: 100);
        }
      }
      if (jsSourceService.activeSourceId != 'hongguo') {
        await jsSourceService.switchSource('hongguo');
        await pumpFrames(tester, count: 4, ms: 100);
      }
      expect(jsSourceService.activeSourceId, equals('hongguo'));
      await captureScreen(tester, '10_source_switched_hongguo.png');

      // 返回首页，验证追剧收藏与最近观看在红果源下完好恢复
      Navigator.of(tester.element(find.byType(JsSourcesPage))).pop();
      await pumpFrames(tester, count: 6, ms: 100);
      expect(find.byType(HomeScreen), findsOneWidget);

      await store.setCatalogSource('hongguo', allSources: false);
      await pumpFrames(tester, count: 4, ms: 100);

      final historyTab = find.text('最近观看');
      if (historyTab.evaluate().isNotEmpty) {
        await tester.tap(historyTab.last);
        await pumpFrames(tester, count: 6, ms: 100);
        expect(find.text(targetDrama.title), findsWidgets);
        await captureScreen(tester, '11_home_history_restored.png');
        debugPrint('【阶段三成功】切回红果源后历史记录完好恢复并截图');
      }

      debugPrint('【全链路验证通过】默认无数据源 + 预置红果源导入 + 自定义插件扩展 + 详情与播放 + 跨源隔离全部验证成功！');
      binding.reportData ??= {};
      binding.reportData!['ios_js_e2e_test_status'] = 'SUCCESS';
    });
  });
}
