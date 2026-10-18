import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/pages/player/player_page.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/search/search_input.dart';

const _fifth = Drama(
  id: 'hongguo:synthetic5',
  source: 'hongguo',
  title: '合成短剧第五季',
  episodes: 2,
);
const _fourth = Drama(
  id: 'hongguo:synthetic4',
  source: 'hongguo',
  title: '合成短剧第四季',
  episodes: 2,
);
DramaDetail _detail(Drama drama) => DramaDetail(drama, [
  for (var i = 1; i <= 2; i++)
    Episode({'id': '${drama.cleanSourceId}_$i', 'title': '第 $i 集'}, i),
]);

class _SeriesRepository extends AppRepository {
  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';

  @override
  Future<DramaDetail> detail(Drama drama) async => _detail(drama);
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async => CatalogPage(const [_fourth, _fifth], hasMore: false);
  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async => const PlaybackPlan(url: 'https://example.invalid/synthetic.mp4');
  @override
  Future<void> cancelPlayback() async {}
  @override
  Future<void> release(String session) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _exactFourth = Drama(
  id: 'hongguo:7688558312157088793',
  source: 'hongguo',
  sourceId: '7688558312157088793',
  title: '满院亲戚全是上古大妖第四季',
  episodes: 155,
);
const _roundedFourth = Drama(
  id: 'hongguo:7688558312157089000',
  source: 'hongguo',
  sourceId: '7688558312157089000',
  title: '满院亲戚全是上古大妖第四季',
  episodes: 155,
);
const _exactSecond = Drama(
  id: 'hongguo:7678338044344159256',
  source: 'hongguo',
  sourceId: '7678338044344159256',
  title: '满院亲戚全是上古大妖第二季',
  episodes: 100,
);
const _roundedSecond = Drama(
  id: 'hongguo:7678338044344159000',
  source: 'hongguo',
  sourceId: '7678338044344159000',
  title: '满院亲戚全是上古大妖第二季',
  episodes: 100,
);
const _exactFifth = Drama(
  id: 'hongguo:7695704804978330649',
  source: 'hongguo',
  sourceId: '7695704804978330649',
  title: '满院亲戚全是上古大妖第五季',
  episodes: 222,
);

class _FreshSeriesRepository extends _SeriesRepository {
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async => CatalogPage(const [
    _exactSecond,
    _exactFourth,
    _exactFifth,
  ], hasMore: false);
}

class _DelayedSeriesRepository extends _FreshSeriesRepository {
  final firstSearch = Completer<CatalogPage>();
  final detailIds = <String>[];
  int searches = 0;
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) {
    if (searches++ == 0) return firstSearch.future;
    return super.catalog(
      source,
      page: page,
      query: query,
      category: category,
      force: force,
    );
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    detailIds.add(drama.id);
    if (hasRoundedHongguoSeriesId(drama)) throw AppFailure('MISSING_EPISODE');
    return _detail(drama);
  }
}

class _UnlistedRoundedRepository extends _SeriesRepository {
  _UnlistedRoundedRepository(this.searchFails);
  final bool searchFails;
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    if (searchFails) throw AppFailure('合成搜索暂不可用');
    return CatalogPage(const []);
  }

  @override
  Future<DramaDetail> detail(Drama drama) async => DramaDetail(drama, [
    Episode({
      'raw':
          'https://hongguoduanju.com/player/${drama.cleanSourceId}/7345678901234567891',
    }, 1),
  ]);
}

class _SeriesPlayer extends LunaExoPlayer {
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    state = state.copyWith(
      playing: play,
      duration: const Duration(minutes: 2),
      position: const Duration(seconds: 5),
      width: 360,
      height: 640,
    );
    stream.durationController.add(state.duration);
    stream.positionController.add(state.position);
  }
}

void main() {
  testWidgets('提交新搜索词时不能选中尚未刷新的旧联想', (tester) async {
    final pending = Completer<List<String>>();
    final controller = TextEditingController();
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchInput(
            controller: controller,
            hint: '合成搜索',
            autofocus: true,
            suggestions: (value) async =>
                value == '都市' ? ['都市合成候选'] : pending.future,
            onSearch: submitted.add,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '都市');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('都市合成候选'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '萌宝');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(submitted, ['萌宝']);
    expect(controller.text, '萌宝');
    pending.complete([]);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('点击联想结果仍按所选完整标题搜索', (tester) async {
    final controller = TextEditingController();
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchInput(
            controller: controller,
            hint: '合成搜索',
            autofocus: true,
            suggestions: (_) async => ['合成短剧第五季'],
            onSearch: submitted.add,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '合成');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-suggestion-0')));
    expect(submitted, ['合成短剧第五季']);
    expect(controller.text, '合成短剧第五季');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('播放器跨季后返回详情和再次播放使用当前季度', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final repository = _SeriesRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          drama: _fifth,
          initialDetail: _detail(_fifth),
          repository: repository,
          store: store,
          initialSeriesEntries: hongguoSeriesEntries(_fifth, const [
            _fourth,
            _fifth,
          ]),
          playerFactory: _SeriesPlayer.new,
          videoBuilder: (controls) => controls,
        ),
      ),
    );
    Future<void> advance() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final start = find.byKey(const ValueKey('start-play'));
    await tester.tap(start);
    await advance();
    expect(
      tester.widget<PlayerScreen>(find.byType(PlayerScreen)).detail.drama.id,
      _fifth.id,
    );
    final fourth = find.byKey(
      const ValueKey('player-season-hongguo:synthetic4'),
    );
    await tester.ensureVisible(fourth);
    await tester.tap(fourth);
    await advance();
    expect(
      tester.widget<PlayerScreen>(find.byType(PlayerScreen)).detail.drama.id,
      _fourth.id,
    );
    Navigator.of(tester.element(find.byType(PlayerScreen))).pop();
    await advance();
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('series-hongguo:synthetic4')),
          )
          .onTap,
      isNull,
    );
    await tester.tap(start);
    await advance();
    expect(
      tester.widget<PlayerScreen>(find.byType(PlayerScreen)).detail.drama.id,
      _fourth.id,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await advance();
    store.dispose();
  });

  test('官方新搜索必须修正已锁定季度中的旧精度丢失编号', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final seeded = LocalStore(prefs);
    await seeded.refreshDramas(const [
      _roundedSecond,
      _roundedFourth,
      _exactFifth,
    ]);
    seeded.dispose();
    final store = LocalStore(prefs);
    addTearDown(store.dispose);
    final entries = await discoverSeriesSeasons(
      anchor: _exactFifth,
      repository: _FreshSeriesRepository(),
      store: store,
      existingEntries: hongguoSeriesEntries(
        _exactFifth,
        store.seriesDramasFor(_exactFifth),
      ),
    );
    expect(entries.singleWhere((e) => e.season == 4).drama.id, _exactFourth.id);
    expect(entries.singleWhere((e) => e.season == 2).drama.id, _exactSecond.id);
  });

  test('旧编号修正后持久化收藏、进度与新季提醒，重启不再选旧编号', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore(prefs);
    final watchedAt = DateTime(2026, 10, 18, 15, 30);
    await store.toggleFavorite(_exactSecond);
    await store.refreshDramas(const [
      _roundedFourth,
      _roundedSecond,
      _exactFifth,
    ]);
    await store.markSeriesSeasonRead(_exactSecond.id, _roundedFourth.id);
    await store.toggleFavorite(_roundedFourth);
    await store.setFollowStatus(_roundedFourth, FollowStatus.watching);
    await store.saveWatch(
      WatchEntry(
        drama: _roundedFourth,
        episode: 12,
        position: 37.5,
        duration: 158,
        updatedAt: watchedAt,
      ),
    );
    await store.refreshDramas(const [_exactFourth, _exactSecond, _exactFifth]);
    store.dispose();
    final restored = LocalStore(prefs);
    addTearDown(restored.dispose);
    expect(restored.isFavorite(_exactFourth.id), isTrue);
    expect(restored.isFavorite(_roundedFourth.id), isFalse);
    final watch = restored.watched(_exactFourth.id)!;
    expect(watch.episode, 12);
    expect(watch.position, 37.5);
    expect(watch.updatedAt, watchedAt);
    expect(restored.watched(_roundedFourth.id), isNull);
    expect(restored.following(_exactFourth.id)!.status, FollowStatus.watching);
    final notices = restored.following(_exactSecond.id)!.seriesSeasons;
    expect(notices.containsKey(_roundedFourth.id), isFalse);
    expect(notices.containsKey(_exactFourth.id), isFalse);
    final seasons = hongguoSeriesEntries(
      _exactFifth,
      restored.seriesDramasFor(_exactFifth),
    );
    expect(seasons.singleWhere((e) => e.season == 4).drama.id, _exactFourth.id);
  });

  test('未单独收藏的新季提醒迁移后保留已读状态', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalStore(prefs);
    await store.toggleFavorite(_exactSecond);
    await store.refreshDramas(const [_roundedFourth]);
    await store.markSeriesSeasonRead(_exactSecond.id, _roundedFourth.id);
    expect(
      store.following(_exactSecond.id)!.seriesSeasons[_roundedFourth.id]!.read,
      isTrue,
    );
    await store.refreshDramas(const [_exactFourth]);
    store.dispose();
    final restored = LocalStore(prefs);
    addTearDown(restored.dispose);
    final notices = restored.following(_exactSecond.id)!.seriesSeasons;
    expect(notices.containsKey(_roundedFourth.id), isFalse);
    expect(notices[_exactFourth.id]!.read, isTrue);
  });

  test('编号迁移与准确编号历史共存时保留较新断点与手动追剧状态', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await store.toggleFavorite(_roundedFourth);
    await store.setFollowStatus(_roundedFourth, FollowStatus.watched);
    await store.toggleFavorite(_exactFourth);
    await store.saveWatch(
      WatchEntry(
        drama: _roundedFourth,
        episode: 12,
        position: 37,
        duration: 158,
        updatedAt: DateTime(2026, 10, 17),
      ),
    );
    await store.saveWatch(
      WatchEntry(
        drama: _exactFourth,
        episode: 33,
        position: 42,
        duration: 100,
        updatedAt: DateTime(2026, 10, 18),
      ),
    );
    await store.refreshDramas(const [_exactFourth]);
    expect(store.favorites, hasLength(1));
    expect(store.watched(_exactFourth.id)!.episode, 33);
    expect(store.watched(_exactFourth.id)!.position, 42);
    expect(store.following(_exactFourth.id)!.manuallyWatched, isTrue);
  });

  test('编号修正仅接受同剧同季且唯一的官方准确结果', () {
    const differentSeason = Drama(
      id: 'hongguo:7688558312157088793',
      source: 'hongguo',
      title: '满院亲戚全是上古大妖第三季',
    );
    const differentTitle = Drama(
      id: 'hongguo:7688558312157088793',
      source: 'hongguo',
      title: '合成另一部短剧第四季',
    );
    const secondExactId = Drama(
      id: 'hongguo:7688558312157088794',
      source: 'hongguo',
      title: '满院亲戚全是上古大妖第四季',
    );
    expect(
      hongguoSeriesIdReplacements(
        [_roundedFourth],
        [differentSeason, differentTitle],
      ),
      isEmpty,
    );
    expect(
      hongguoSeriesIdReplacements(
        [_roundedFourth],
        [_exactFourth, secondExactId],
      ),
      isEmpty,
    );
    expect(
      hongguoSeriesIdReplacements([_exactFourth], [_roundedFourth]),
      isEmpty,
    );
    expect(
      hongguoSeriesIdReplacements(
        [_roundedFourth],
        [_exactFourth],
      )[_roundedFourth.id]!.id,
      _exactFourth.id,
    );
    const variantTitle = Drama(
      id: 'hongguo:7688558312157089000',
      source: 'hongguo',
      title: '满院亲戚全是上古大妖 第4季 (全集)',
    );
    expect(
      hongguoSeriesIdReplacements(
        [variantTitle],
        [_exactFourth],
      )[variantTitle.id]!.id,
      _exactFourth.id,
    );
  });

  test('旧编号点击后必须重新查证，不能从失真数字猜出原始编号', () async {
    final corrected = await resolveHongguoSeriesIdentity(
      drama: _roundedFourth,
      repository: _FreshSeriesRepository(),
    );
    expect(corrected.cleanSourceId, '7688558312157088793');
    expect(
      () => resolveHongguoSeriesIdentity(
        drama: _roundedFourth,
        repository: _SeriesRepository(),
      ),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'STALE_SERIES_ID'),
      ),
    );
  });

  test('仅凭末尾为零不能拒绝官方确有准确分集的合法编号', () async {
    for (final searchFails in [false, true]) {
      final verified = await resolveHongguoSeriesIdentity(
        drama: _roundedFourth,
        repository: _UnlistedRoundedRepository(searchFails),
      );
      expect(verified.id, _roundedFourth.id);
      expect(verified.cleanSourceId, _roundedFourth.cleanSourceId);
    }
  });

  testWidgets('网络刷新未完成时点击旧季度，播放器仍使用查证后的准确编号', (tester) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    await store.refreshDramas(const [_roundedFourth, _exactFifth]);
    final repository = _DelayedSeriesRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          drama: _exactFifth,
          initialDetail: _detail(_exactFifth),
          repository: repository,
          store: store,
          initialSeriesEntries: hongguoSeriesEntries(_exactFifth, const [
            _roundedFourth,
            _exactFifth,
          ]),
          playerFactory: _SeriesPlayer.new,
          videoBuilder: (controls) => controls,
        ),
      ),
    );
    Future<void> advance() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.byKey(const ValueKey('start-play')));
    await advance();
    final old = find.byKey(
      const ValueKey('player-season-hongguo:7688558312157089000'),
    );
    await tester.ensureVisible(old);
    await tester.tap(old);
    await advance();
    expect(repository.detailIds, [_exactFourth.id]);
    expect(
      tester.widget<PlayerScreen>(find.byType(PlayerScreen)).detail.drama.id,
      _exactFourth.id,
    );
    repository.firstSearch.complete(
      CatalogPage(const [_exactSecond, _exactFourth, _exactFifth]),
    );
    await advance();
    Navigator.of(tester.element(find.byType(PlayerScreen))).pop();
    await advance();
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const ValueKey('series-hongguo:7688558312157088793')),
          )
          .onTap,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('series-hongguo:7688558312157089000')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await advance();
    store.dispose();
  });

  group('官方多季剧集识别与聚合引擎 (Hongguo Multi-Season Engine) 测试', () {
    test('1. 基础标题清洗 (去除画质与状态杂质)', () {
      expect(cleanSeriesBaseTitle('盖世龙王 (4K高清全集)'), equals('盖世龙王'));
      expect(cleanSeriesBaseTitle('赘婿当道 [1080P完结]'), equals('赘婿当道'));
      expect(cleanSeriesBaseTitle('九天仙尊【精修版】'), equals('九天仙尊'));
      expect(cleanSeriesBaseTitle('至尊神相（热播已完结）'), equals('至尊神相'));
    });

    test('2. 中文数字与常规季数识别 (第X季/部/篇)', () {
      final drama1 = Drama(
        id: 'hongguo:101',
        source: 'hongguo',
        sourceId: '101',
        title: '都市绝品仙医 第一季',
      );
      final info1 = hongguoSeriesInfo(drama1);
      expect(info1, isNotNull);
      expect(info1!.baseTitle, equals('都市绝品仙医'));
      expect(info1.season, equals(1));
      expect(info1.unit, equals('季'));

      final drama2 = Drama(
        id: 'hongguo:102',
        source: 'hongguo',
        sourceId: '102',
        title: '都市绝品仙医 第二季',
      );
      final info2 = hongguoSeriesInfo(drama2);
      expect(info2, isNotNull);
      expect(info2!.season, equals(2));

      final drama3 = Drama(
        id: 'hongguo:103',
        source: 'hongguo',
        sourceId: '103',
        title: '都市绝品仙医 第十二季',
      );
      final info3 = hongguoSeriesInfo(drama3);
      expect(info3, isNotNull);
      expect(info3!.season, equals(12));
    });

    test('3. 英文 Season / S 标识与罗马数字季数识别', () {
      final dramaS2 = Drama(
        id: 'hongguo:201',
        source: 'hongguo',
        sourceId: '201',
        title: '狂飙之风云际会 S2',
      );
      final infoS2 = hongguoSeriesInfo(dramaS2);
      expect(infoS2, isNotNull);
      expect(infoS2!.season, equals(2));

      final dramaSeason3 = Drama(
        id: 'hongguo:202',
        source: 'hongguo',
        sourceId: '202',
        title: '狂飙之风云际会 Season 3',
      );
      final infoSeason3 = hongguoSeriesInfo(dramaSeason3);
      expect(infoSeason3, isNotNull);
      expect(infoSeason3!.season, equals(3));

      final dramaRoman = Drama(
        id: 'hongguo:203',
        source: 'hongguo',
        sourceId: '203',
        title: '狂飙之风云际会 II',
      );
      final infoRoman = hongguoSeriesInfo(dramaRoman);
      expect(infoRoman, isNotNull);
      expect(infoRoman!.season, equals(2));
    });

    test('4. 续集/大结局词缀识别', () {
      final dramaSequel = Drama(
        id: 'hongguo:301',
        source: 'hongguo',
        sourceId: '301',
        title: '霸道总裁的小娇妻 续集',
      );
      final infoSequel = hongguoSeriesInfo(dramaSequel);
      expect(infoSequel, isNotNull);
      expect(infoSequel!.season, equals(2));

      final dramaFinal = Drama(
        id: 'hongguo:302',
        source: 'hongguo',
        sourceId: '302',
        title: '霸道总裁的小娇妻 大结局',
      );
      final infoFinal = hongguoSeriesInfo(dramaFinal);
      expect(infoFinal, isNotNull);
      expect(infoFinal!.season, equals(99));
    });

    test('5. 多季聚拢 (hongguoSeriesEntries) 排序与展示测试', () {
      final anchor = Drama(
        id: 'hongguo:1001',
        source: 'hongguo',
        sourceId: '1001',
        title: '天命大反派',
      );

      final s1 = Drama(
        id: 'hongguo:1001',
        source: 'hongguo',
        sourceId: '1001',
        title: '天命大反派 第一季',
      );
      final s2 = Drama(
        id: 'hongguo:1002',
        source: 'hongguo',
        sourceId: '1002',
        title: '天命大反派 第二季',
      );
      final s3 = Drama(
        id: 'hongguo:1003',
        source: 'hongguo',
        sourceId: '1003',
        title: '天命大反派 第三季',
      );

      final entries = hongguoSeriesEntries(anchor, [s1, s2, s3]);
      expect(entries.length, equals(3));
      expect(entries[0].season, equals(1));
      expect(entries[0].label, equals('第 1 季'));
      expect(entries[1].season, equals(2));
      expect(entries[1].label, equals('第 2 季'));
      expect(entries[2].season, equals(3));
      expect(entries[2].label, equals('第 3 季'));
    });
  });
}
