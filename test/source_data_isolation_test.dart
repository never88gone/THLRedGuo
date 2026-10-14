import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/downloads_screen.dart';
import 'package:THLRedLook/js_source_models.dart';
import 'package:THLRedLook/js_source_presets.dart';
import 'package:THLRedLook/js_source_service.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/saved_library.dart';

import 'fixtures.dart';

class IsolationTestRepository extends FixtureRepository {
  final Map<String, JsSourceMeta> _installedJsSources = {};
  String _activeJsSourceId = '';
  final List<DownloadJob> _downloads = [];

  void setDownloads(List<DownloadJob> jobs) {
    _downloads.clear();
    _downloads.addAll(jobs);
  }

  @override
  Future<List<DownloadJob>> downloads() async => List.unmodifiable(_downloads);

  @override
  Future<List<JsSourceMeta>> jsSourceList() async => _installedJsSources.values.toList();

  @override
  Future<bool> jsSourceSetActive(String sourceId) async {
    _activeJsSourceId = sourceId;
    return true;
  }

  @override
  Future<String> jsSourceGetActive() async => _activeJsSourceId;

  @override
  Future<bool> jsSourceSaveAndLoad(String script, String fileName) async {
    final idMatch = RegExp(r'id:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(script);
    final nameMatch = RegExp(r'name:\s*["\x27]([^"\x27]+)["\x27]').firstMatch(script);
    if (idMatch == null || nameMatch == null) return false;

    final id = idMatch.group(1)!.trim();
    final name = nameMatch.group(1)!.trim();
    _installedJsSources[id] = JsSourceMeta(
      id: id,
      name: name,
      version: '1.0.0',
      description: name,
      features: ['playback'],
    );
    return true;
  }
}

Future<LocalStore> _createStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return testStore(prefs);
}

void main() {
  setUp(() {
    SourceSite.resetRuntimeActivation();
  });

  tearDown(() {
    JsSourceService.current = null;
  });

  group('数据源完全隔离（Data Isolation per Source）测试', () {
    testWidgets('1. 验证最近播放（Watch History）按数据源完全隔离，数据绝不跨源泄露', (tester) async {
      final store = await _createStore();
      addTearDown(store.dispose);

      final repo = IsolationTestRepository();
      final jsSourceService = JsSourceService(repo, store.preferences);
      for (final preset in kPresetJsSources) {
        await jsSourceService.importScript(preset.script, preset.fileName);
      }

      // 在 hongguo 源下存入播放记录
      final hgDrama = const Drama(
        id: 'hongguo:hg_101',
        source: 'hongguo',
        title: '红果短剧 1',
        episodes: 20,
      );
      await store.saveWatch(WatchEntry(
        drama: hgDrama,
        episode: 3,
        position: 45.0,
        duration: 120.0,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ));

      // 在 hanxiaoquan 源下存入播放记录
      final hxqDrama = const Drama(
        id: 'hanxiaoquan:hxq_201',
        source: 'hanxiaoquan',
        title: '韩小圈韩剧 1',
        episodes: 16,
      );
      await store.saveWatch(WatchEntry(
        drama: hxqDrama,
        episode: 1,
        position: 18.0,
        duration: 60.0,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));

      // 在 yeguo 源下存入播放记录
      final ygDrama = const Drama(
        id: 'yeguo:yg_301',
        source: 'yeguo',
        title: '野果逆袭剧 1',
        episodes: 30,
      );
      await store.saveWatch(WatchEntry(
        drama: ygDrama,
        episode: 5,
        position: 90.0,
        duration: 100.0,
        updatedAt: DateTime.now(),
      ));

      // 验证：切换到 hongguo 时，只显示 hongguo 的播放记录
      await jsSourceService.switchSource('hongguo');
      await store.setCatalogSource('hongguo', allSources: false);

      final hgHistory = store.currentHistory;
      expect(hgHistory.length, equals(1));
      expect(hgHistory.first.drama.id, equals('hongguo:hg_101'));
      expect(hgHistory.first.drama.source, equals('hongguo'));
      expect(hgHistory.any((e) => e.drama.source == 'hanxiaoquan'), isFalse);
      expect(hgHistory.any((e) => e.drama.source == 'yeguo'), isFalse);

      // 验证：切换到 hanxiaoquan 时，只显示 hanxiaoquan 的播放记录
      await jsSourceService.switchSource('hanxiaoquan');
      await store.setCatalogSource('hanxiaoquan', allSources: false);

      final hxqHistory = store.currentHistory;
      expect(hxqHistory.length, equals(1));
      expect(hxqHistory.first.drama.id, equals('hanxiaoquan:hxq_201'));
      expect(hxqHistory.first.drama.source, equals('hanxiaoquan'));
      expect(hxqHistory.any((e) => e.drama.source == 'hongguo'), isFalse);
      expect(hxqHistory.any((e) => e.drama.source == 'yeguo'), isFalse);

      // 验证：切换到 yeguo 时，只显示 yeguo 的播放记录
      await jsSourceService.switchSource('yeguo');
      await store.setCatalogSource('yeguo', allSources: false);

      final ygHistory = store.currentHistory;
      expect(ygHistory.length, equals(1));
      expect(ygHistory.first.drama.id, equals('yeguo:yg_301'));
      expect(ygHistory.first.drama.source, equals('yeguo'));
      expect(ygHistory.any((e) => e.drama.source == 'hongguo'), isFalse);
      expect(ygHistory.any((e) => e.drama.source == 'hanxiaoquan'), isFalse);
    });

    testWidgets('2. 验证我的追剧（Favorites）按数据源完全隔离', (tester) async {
      final store = await _createStore();
      addTearDown(store.dispose);

      final hgDrama = const Drama(id: 'hongguo:hg_fav', source: 'hongguo', title: '红果追剧');
      final hxqDrama = const Drama(id: 'hanxiaoquan:hxq_fav', source: 'hanxiaoquan', title: '韩小圈追剧');

      await store.toggleFavorite(hgDrama);
      await store.toggleFavorite(hxqDrama);

      // 切换至 hongguo
      await store.setCatalogSource('hongguo', allSources: false);
      final hgFavs = store.currentFavorites;
      expect(hgFavs.length, equals(1));
      expect(hgFavs.first.id, equals('hongguo:hg_fav'));

      // 切换至 hanxiaoquan
      await store.setCatalogSource('hanxiaoquan', allSources: false);
      final hxqFavs = store.currentFavorites;
      expect(hxqFavs.length, equals(1));
      expect(hxqFavs.first.id, equals('hanxiaoquan:hxq_fav'));
    });

    testWidgets('3. 验证当前数据源清空播放记录（clearHistory）不影响其他数据源', (tester) async {
      final store = await _createStore();
      addTearDown(store.dispose);

      final hgDrama = const Drama(id: 'hongguo:hg_del', source: 'hongguo', title: '红果待删');
      final hxqDrama = const Drama(id: 'hanxiaoquan:hxq_keep', source: 'hanxiaoquan', title: '韩小圈保留');

      await store.saveWatch(WatchEntry(
        drama: hgDrama,
        episode: 1,
        position: 10,
        duration: 50,
        updatedAt: DateTime.now(),
      ));
      await store.saveWatch(WatchEntry(
        drama: hxqDrama,
        episode: 2,
        position: 20,
        duration: 60,
        updatedAt: DateTime.now(),
      ));

      // 处于 hongguo 源下，调用清空历史
      await store.setCatalogSource('hongguo', allSources: false);
      await store.clearHistory();

      // 验证 hongguo 的播放记录已清空
      expect(store.currentHistory, isEmpty);

      // 验证切换到 hanxiaoquan 后，其播放记录依然完整保留
      await store.setCatalogSource('hanxiaoquan', allSources: false);
      expect(store.currentHistory.length, equals(1));
      expect(store.currentHistory.first.drama.id, equals('hanxiaoquan:hxq_keep'));
    });

    testWidgets('4. 验证 SavedLibrary UI 组件在切换数据源后严格仅展示当前源播放记录', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final store = await _createStore();
      addTearDown(store.dispose);
      final repo = IsolationTestRepository();

      final hgDrama = const Drama(id: 'hongguo:hg_ui', source: 'hongguo', title: '红果UI短剧');
      final hxqDrama = const Drama(id: 'hanxiaoquan:hxq_ui', source: 'hanxiaoquan', title: '韩小圈UI剧集');

      await store.saveWatch(WatchEntry(
        drama: hgDrama,
        episode: 1,
        position: 10,
        duration: 100,
        updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      ));
      await store.saveWatch(WatchEntry(
        drama: hxqDrama,
        episode: 3,
        position: 30,
        duration: 150,
        updatedAt: DateTime.now(),
      ));
      await store.setCatalogSource('hongguo', allSources: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SavedLibrary(
              repository: repo,
              store: store,
              history: true,
              onOpen: (_) {},
              onContinue: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言当前界面只渲染红果剧集，韩小圈剧集绝不出现
      expect(find.text('红果UI短剧'), findsOneWidget);
      expect(find.text('韩小圈UI剧集'), findsNothing);
      expect(find.textContaining('最近观看 · 1'), findsOneWidget);

      // 切换数据源至 hanxiaoquan 并刷新组件
      await store.setCatalogSource('hanxiaoquan', allSources: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言界面即时变为韩小圈剧集，红果剧集绝不出现
      expect(find.text('韩小圈UI剧集'), findsOneWidget);
      expect(find.text('红果UI短剧'), findsNothing);
      expect(find.textContaining('最近观看 · 1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('5. 验证 DownloadsScreen 离线下载列表仅展示当前数据源的任务', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final store = await _createStore();
      addTearDown(store.dispose);

      final hgDrama = const Drama(id: 'hongguo:hg_dl', source: 'hongguo', title: '红果下载剧');
      final hxqDrama = const Drama(id: 'hanxiaoquan:hxq_dl', source: 'hanxiaoquan', title: '韩小圈下载剧');

      final repo = IsolationTestRepository();
      repo.setDownloads([
        DownloadJob(
          id: 'job_hg_1',
          drama: hgDrama,
          episode: Episode({'id': 'hg_ep1', 'title': '第1集'}, 1),
          state: 'completed',
          progress: 1.0,
          bytes: 1024,
          total: 1024,
        ),
        DownloadJob(
          id: 'job_hxq_1',
          drama: hxqDrama,
          episode: Episode({'id': 'hxq_ep1', 'title': '第1集'}, 1),
          state: 'completed',
          progress: 1.0,
          bytes: 2048,
          total: 2048,
        ),
      ]);

      // 切换至 hongguo 源
      await store.setCatalogSource('hongguo', allSources: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: DownloadsScreen(
              repository: repo,
              store: store,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 只展示红果下载剧
      expect(find.text('红果下载剧'), findsOneWidget);
      expect(find.text('韩小圈下载剧'), findsNothing);

      // 切换至 hanxiaoquan 源
      await store.setCatalogSource('hanxiaoquan', allSources: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 只展示韩小圈下载剧
      expect(find.text('韩小圈下载剧'), findsOneWidget);
      expect(find.text('红果下载剧'), findsNothing);

      // 卸载组件以触发 dispose() 取消内部的 periodic timer
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
