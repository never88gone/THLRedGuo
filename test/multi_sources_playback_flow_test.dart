import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/js_source_models.dart';
import 'package:THLRedLook/js_source_presets.dart';
import 'package:THLRedLook/js_source_service.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

/// 能够模拟多数据源独立目录、详情与播放取流的 E2E 仓储
class MultiSourcePlaybackRepository extends FixtureRepository {
  final Map<String, JsSourceMeta> _installedJsSources = {};
  String _activeJsSourceId = '';
  final List<String> resolvedPlaybackUrls = [];
  final List<Map<String, String>> resolvedPlaybackHeaders = [];
  final List<String> releaseSessions = [];

  // 各数据源的特征视频流地址
  static const Map<String, String> expectedUrls = {
    'hongguo': 'https://cenc.hongguo.test/stream/700101/1_1080p.mp4',
    'hanxiaoquan': 'https://hanxiaoquan.tv/video/hxq_101_ep1.m3u8',
    'yeguo': 'https://yeguo.cc/stream/yg_201_ep1/playlist.m3u8',
    'huangdou': 'https://tideember.cc/play/hd_301_ep1/index.m3u8',
    'dsd': 'https://www.dsd.com.se/video/dsd_401_ep1/stream.m3u8',
  };

  @override
  Future<void> initialize() async {}

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
    final meta = JsSourceMeta(
      id: id,
      name: name,
      version: '1.0.1',
      description: '$name 插件',
      features: ['search', 'categories', 'playback'],
    );
    _installedJsSources[id] = meta;
    if (_activeJsSourceId.isEmpty) {
      _activeJsSourceId = id;
    }
    return true;
  }

  @override
  Future<List<CatalogCategory>> categories(String source, {bool force = false}) async {
    return [
      CatalogCategory.all,
      CatalogCategory('${source}_cat1', '$source精选'),
      CatalogCategory('${source}_cat2', '$source热门'),
    ];
  }

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    return CatalogPage([
      Drama(
        id: '$source:${source}_101',
        source: source,
        title: '$source专属剧集 1',
        episodes: 20,
        category: category.isNotEmpty ? category : '全部',
      ),
      Drama(
        id: '$source:${source}_102',
        source: source,
        title: '$source专属剧集 2',
        episodes: 40,
        category: category.isNotEmpty ? category : '全部',
      ),
    ], page: page, hasMore: false);
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    final source = drama.source;
    return DramaDetail(
      drama,
      List.generate(
        drama.episodes > 0 ? drama.episodes : 5,
        (index) {
          final epNum = index + 1;
          return Episode({
            'id': '${source}_ep$epNum',
            'currentEpisode': epNum,
            'title': '第$epNum集',
          }, epNum);
        },
      ),
    );
  }

  @override
  Future<PlaybackPlan> resolve(Drama drama, Episode episode, {int quality = 0}) async {
    return resolveOnline(drama, episode, quality: quality);
  }

  @override
  Future<PlaybackPlan> resolveOnline(Drama drama, Episode episode, {int quality = 0}) async {
    final source = drama.source;
    final url = expectedUrls[source] ?? 'https://generic.stream.test/$source/${episode.number}.mp4';
    final headers = <String, String>{
      'User-Agent': '$source/Client',
      if (source != 'huangdou') 'Referer': 'https://$source.test/',
    };

    resolvedPlaybackUrls.add(url);
    resolvedPlaybackHeaders.add(headers);

    return PlaybackPlan(
      url: url,
      session: 'session_${source}_${episode.number}_${DateTime.now().microsecondsSinceEpoch}',
      headers: headers,
    );
  }

  @override
  Future<void> cancelPlayback() async {}

  @override
  Future<void> release(String session) async {
    releaseSessions.add(session);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MultiSourcePlaybackRepository repository;
  late SharedPreferences preferences;
  late LocalStore store;
  late JsSourceService jsSourceService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    repository = MultiSourcePlaybackRepository();
    jsSourceService = JsSourceService(repository, preferences);
    store = LocalStore(preferences);
    SourceSite.resetRuntimeActivation();
  });

  tearDown(() {
    JsSourceService.current = null;
  });

  group('多数据源导入、切换与各源视频起播全链路闭环测试', () {
    test('1. 验证 5 大主流短剧数据源全部正常导入并完成插件注册', () async {
      expect(kPresetJsSources.length, greaterThanOrEqualTo(5));

      for (final preset in kPresetJsSources) {
        final success = await jsSourceService.importScript(preset.script, preset.fileName);
        expect(success, isTrue, reason: '导入 ${preset.name} 应成功');
      }

      final installed = jsSourceService.sources;
      expect(installed.length, equals(kPresetJsSources.length));

      // 验证全部 5 个源的 ID 均已安装
      final installedIds = installed.map((s) => s.id).toSet();
      expect(installedIds, containsAll(['hongguo', 'hanxiaoquan', 'yeguo', 'huangdou', 'dsd']));

      // 验证 SourceSite 集合中内置源与已导入源并存
      final siteIds = SourceSite.values.map((s) => s.id).toSet();
      expect(siteIds, containsAll(['hongguo', 'hanxiaoquan', 'yeguo', 'huangdou', 'dsd']));
      for (final id in ['hongguo', 'hanxiaoquan', 'yeguo', 'huangdou', 'dsd']) {
        expect(SourceSite.isAvailable(id), isTrue);
        expect(store.allowsSource(id), isTrue);
      }
    });

    test('2. 验证各个数据源平滑切换，状态单向收敛且无震荡', () async {
      // 预先导入全部数据源
      for (final preset in kPresetJsSources) {
        await jsSourceService.importScript(preset.script, preset.fileName);
      }

      final testOrder = ['hongguo', 'hanxiaoquan', 'yeguo', 'huangdou', 'dsd', 'hongguo'];

      for (final targetId in testOrder) {
        // 执行切换
        await jsSourceService.switchSource(targetId);
        await store.setCatalogSource(targetId, allSources: false);

        expect(jsSourceService.activeSourceId, equals(targetId));
        expect(store.source, equals(targetId));
        expect(store.allowsSource(targetId), isTrue);

        // 验证当前数据源的分类与剧集拉取准确隔离
        final cats = await repository.categories(targetId);
        expect(cats.length, greaterThanOrEqualTo(2));
        expect(cats[1].id, contains(targetId));

        final catalogPage = await repository.catalog(targetId);
        expect(catalogPage.items.isNotEmpty, isTrue);
        expect(catalogPage.items.first.source, equals(targetId));
        expect(catalogPage.items.first.id, startsWith('$targetId:'));
      }
    });

    test('3. 验证 5 大主流短剧数据源各自独立的视频解析取流与防盗链闭环', () async {
      // 预先导入全部数据源
      for (final preset in kPresetJsSources) {
        await jsSourceService.importScript(preset.script, preset.fileName);
      }

      final sourcesToVerify = ['hongguo', 'hanxiaoquan', 'yeguo', 'huangdou', 'dsd'];

      for (final sourceId in sourcesToVerify) {
        // 1. 切换至目标数据源
        await jsSourceService.switchSource(sourceId);
        await store.setCatalogSource(sourceId, allSources: false);

        // 2. 获取该数据源的短剧与详情
        final catalog = await repository.catalog(sourceId);
        final drama = catalog.items.first;
        final detail = await repository.detail(drama);

        expect(detail.drama.source, equals(sourceId));
        expect(detail.episodes.isNotEmpty, isTrue);

        // 3. 验证通过取流解析生成该数据源专属的 PlaybackPlan
        final episode = detail.episodes.first;
        final plan = await repository.resolveOnline(drama, episode);

        expect(plan.url, equals(MultiSourcePlaybackRepository.expectedUrls[sourceId]),
            reason: '$sourceId 应解析到对应的专属视频流地址');
        expect(plan.session.isNotEmpty, isTrue);
        expect(plan.headers['User-Agent'], equals('$sourceId/Client'));
        if (sourceId != 'huangdou') {
          expect(plan.headers['Referer'], contains(sourceId));
        }

        // 验证播放计划可正常释放
        await repository.release(plan.session);
        expect(repository.releaseSessions, contains(plan.session));
      }
    });

    testWidgets('4. 验证数据源切换后在 PlayerScreen 中的真实挂载起播与状态流转闭环', (tester) async {
      // 1. 模拟切换至 JS 插件站源（如 hanxiaoquan）的剧集
      final hxqDrama = Drama(
        id: 'hanxiaoquan:hxq_101',
        source: 'hanxiaoquan',
        title: '韩小圈专属短剧',
        episodes: 10,
        category: '精选韩剧',
      );
      final hxqDetail = await repository.detail(hxqDrama);
      final platformPlayer = ScriptedPlayer();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: PlayerScreen(
            detail: hxqDetail,
            initialIndex: 0,
            initialPosition: 0,
            repository: repository,
            store: store,
            playerFactory: () => Player(platformPlayer: platformPlayer),
            videoBuilder: (controls) => controls,
          ),
        ),
      );

      // 推进时钟驱动 PlayerScreen 初始化和异步起播流程
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // 验证播放器 open 被正确触发，且地址为目标数据源的专属地址
      expect(platformPlayer.opened.isNotEmpty, isTrue, reason: '应成功调用底层播放器起播');
      expect(
        platformPlayer.opened.last.uri,
        equals(MultiSourcePlaybackRepository.expectedUrls['hanxiaoquan']),
        reason: '播放地址应匹配韩小圈专属流',
      );

      // 模拟底层播放器推流状态变更：buffering -> playing
      platformPlayer.bufferingController.add(false);
      platformPlayer.playingController.add(true);
      platformPlayer.positionController.add(const Duration(seconds: 8));

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(platformPlayer.state.playing, isTrue);

      // 安全卸载播放组件
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(platformPlayer.disposed, isTrue);
      expect(repository.releaseSessions.isNotEmpty, isTrue);
    });

    testWidgets('5. 验证红果原生数据源与野果插件源在 PlayerScreen 中的挂载起播与流转', (tester) async {
      // 1. 验证红果原生数据源剧集起播
      final hgDrama = Drama(
        id: 'hongguo:700101',
        source: 'hongguo',
        title: '红果热门剧集',
        episodes: 20,
        category: '精选短剧',
      );
      final hgDetail = await repository.detail(hgDrama);
      final hgPlayer = ScriptedPlayer();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: PlayerScreen(
            detail: hgDetail,
            initialIndex: 0,
            initialPosition: 0,
            repository: repository,
            store: store,
            playerFactory: () => Player(platformPlayer: hgPlayer),
            videoBuilder: (controls) => controls,
          ),
        ),
      );

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(hgPlayer.opened.isNotEmpty, isTrue);
      expect(
        hgPlayer.opened.last.uri,
        equals(MultiSourcePlaybackRepository.expectedUrls['hongguo']),
        reason: '红果源应起播对应的红果视频流',
      );

      // 卸载红果播放器
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(hgPlayer.disposed, isTrue);

      // 2. 验证切换至野果插件源剧集并起播
      final ygDrama = Drama(
        id: 'yeguo:yg_201',
        source: 'yeguo',
        title: '野果分类剧集',
        episodes: 15,
        category: '反转爽剧',
      );
      final ygDetail = await repository.detail(ygDrama);
      final ygPlayer = ScriptedPlayer();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: PlayerScreen(
            detail: ygDetail,
            initialIndex: 0,
            initialPosition: 0,
            repository: repository,
            store: store,
            playerFactory: () => Player(platformPlayer: ygPlayer),
            videoBuilder: (controls) => controls,
          ),
        ),
      );

      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(ygPlayer.opened.isNotEmpty, isTrue);
      expect(
        ygPlayer.opened.last.uri,
        equals(MultiSourcePlaybackRepository.expectedUrls['yeguo']),
        reason: '野果源应起播对应的野果视频流',
      );

      // 模拟野果播放器缓冲完成并播放
      ygPlayer.bufferingController.add(false);
      ygPlayer.playingController.add(true);
      ygPlayer.positionController.add(const Duration(seconds: 12));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(ygPlayer.state.playing, isTrue);

      // 卸载野果播放器
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(ygPlayer.disposed, isTrue);
    });
  });
}
