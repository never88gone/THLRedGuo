import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:THLRedLook/hongguo_series.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/views/player/player_episodes_sheet_view.dart';
import 'package:THLRedLook/views/player/player_desktop_panel_view.dart';
import 'package:THLRedLook/views/player/player_mobile_panel_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixtures.dart';

class _MockSeriesRepository extends FixtureRepository {
  _MockSeriesRepository({required this.searchDramas});
  final List<Drama> searchDramas;

  @override
  Future<CatalogPage> catalog(
    String source, {
    String category = '',
    String query = '',
    int page = 1,
    bool force = false,
  }) async {
    return CatalogPage(searchDramas);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('系列多季识别引擎测试 (Series Parser & Stripper)', () {
    test('标题噪声清洗与标准中文季数识别', () {
      const drama1 = Drama(
        id: 's1',
        source: 'hongguo',
        title: '都市绝品战神 第一季 (全集)',
      );
      final info1 = hongguoSeriesInfo(drama1);
      expect(info1, isNotNull);
      expect(info1!.baseTitle, '都市绝品战神');
      expect(info1.season, 1);
      expect(info1.unit, '季');

      const drama2 = Drama(
        id: 's2',
        source: 'hongguo',
        title: '都市绝品战神 第二部 【4K超清】',
      );
      final info2 = hongguoSeriesInfo(drama2);
      expect(info2, isNotNull);
      expect(info2!.baseTitle, '都市绝品战神');
      expect(info2.season, 2);
      expect(info2.unit, '部');

      const drama3 = Drama(
        id: 's3',
        source: 'hongguo',
        title: '大夏龙王 第3篇 (80集完结)',
      );
      final info3 = hongguoSeriesInfo(drama3);
      expect(info3, isNotNull);
      expect(info3!.baseTitle, '大夏龙王');
      expect(info3.season, 3);
      expect(info3.unit, '篇');
    });

    test('英文、罗马数字、纯数字与续集词缀识别', () {
      const dramaEn = Drama(
        id: 'en',
        source: 'hongguo',
        title: 'My Hero Season 2',
      );
      final infoEn = hongguoSeriesInfo(dramaEn);
      expect(infoEn, isNotNull);
      expect(infoEn!.season, 2);
      expect(infoEn.unit, '季');

      const dramaRoman = Drama(
        id: 'roman',
        source: 'hongguo',
        title: '巅峰归来 III',
      );
      final infoRoman = hongguoSeriesInfo(dramaRoman);
      expect(infoRoman, isNotNull);
      expect(infoRoman!.season, 3);

      const dramaNum = Drama(
        id: 'num',
        source: 'hongguo',
        title: '隐龙出世 2',
      );
      final infoNum = hongguoSeriesInfo(dramaNum);
      expect(infoNum, isNotNull);
      expect(infoNum!.season, 2);

      const dramaSequel = Drama(
        id: 'seq',
        source: 'hongguo',
        title: '千亿总裁 续集',
      );
      final infoSeq = hongguoSeriesInfo(dramaSequel);
      expect(infoSeq, isNotNull);
      expect(infoSeq!.season, 2);
    });

    test('基础系列名称清洗 cleanSeriesBaseTitle', () {
      expect(cleanSeriesBaseTitle('风云再起 第一季 (全集)'), '风云再起');
      expect(cleanSeriesBaseTitle('风云再起 第2季'), '风云再起');
      expect(cleanSeriesBaseTitle('风云再起 Season 3'), '风云再起');
      expect(cleanSeriesBaseTitle('风云再起 2'), '风云再起');
    });

    test('多季聚合排序 hongguoSeriesEntries', () {
      const plainSeasonOne = Drama(
        id: 'd1',
        source: 'hongguo',
        title: '天王殿',
      );
      const explicitSeasonTwo = Drama(
        id: 'd2',
        source: 'hongguo',
        title: '天王殿 第二季',
      );
      const explicitSeasonThree = Drama(
        id: 'd3',
        source: 'hongguo',
        title: '天王殿 第三季',
      );

      final entriesFromOne = hongguoSeriesEntries(
        plainSeasonOne,
        [plainSeasonOne, explicitSeasonTwo, explicitSeasonThree],
      );
      expect(entriesFromOne.length, 3);
      expect(entriesFromOne[0].drama.id, 'd1');
      expect(entriesFromOne[0].season, 1);
      expect(entriesFromOne[1].drama.id, 'd2');
      expect(entriesFromOne[1].season, 2);
      expect(entriesFromOne[2].drama.id, 'd3');
      expect(entriesFromOne[2].season, 3);

      final entriesFromTwo = hongguoSeriesEntries(
        explicitSeasonTwo,
        [plainSeasonOne, explicitSeasonTwo],
      );
      expect(entriesFromTwo.length, 2);
      expect(entriesFromTwo[0].season, 1);
      expect(entriesFromTwo[1].season, 2);

      // 单剧集不构成多季
      final singleEntries = hongguoSeriesEntries(
        plainSeasonOne,
        [plainSeasonOne],
      );
      expect(singleEntries.isEmpty, isTrue);
    });
  });

  group('系列多季主动发现机制 (discoverSeriesSeasons)', () {
    test('通过源站检索主动聚拢未缓存的多季', () async {
      final repository = _MockSeriesRepository(
        searchDramas: [
          const Drama(
            id: 'c1',
            source: 'hongguo',
            title: '无双龙婿',
          ),
          const Drama(
            id: 'c2',
            source: 'hongguo',
            title: '无双龙婿 第二季',
          ),
        ],
      );

      const anchor = Drama(
        id: 'c1',
        source: 'hongguo',
        title: '无双龙婿',
      );

      final discovered = await discoverSeriesSeasons(
        anchor: anchor,
        repository: repository,
      );

      expect(discovered.length, 2);
      expect(discovered.map((e) => e.drama.id), containsAll(['c1', 'c2']));
    });
  });

  group('播放选集界面多季展示与快速切换组件测试', () {
    testWidgets('PlayerEpisodesSheetView 渲染多季胶囊并支持切季回调', (tester) async {
      const dramaS1 = Drama(
        id: 'd_s1',
        source: 'hongguo',
        title: '狂龙出狱',
        episodes: 10,
      );
      const dramaS2 = Drama(
        id: 'd_s2',
        source: 'hongguo',
        title: '狂龙出狱 第二季',
        episodes: 10,
      );

      final series = [
        const HongguoSeriesEntry(drama: dramaS1, season: 1, unit: '季'),
        const HongguoSeriesEntry(drama: dramaS2, season: 2, unit: '季'),
      ];

      Drama? selectedSeason;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerEpisodesSheetView(
              episodes: List.generate(
                10,
                (i) => Episode({'id': 'ep_$i', 'title': '第${i + 1}集'}, i + 1),
              ),
              currentIndex: 0,
              dramaTitle: dramaS1.title,
              seriesEntries: series,
              currentDramaId: dramaS1.id,
              onEpisodeSelected: (_) {},
              onSeasonSelected: (seasonDrama) {
                selectedSeason = seasonDrama;
              },
            ),
          ),
        ),
      );

      expect(find.text('系列多季'), findsOneWidget);
      expect(find.text('共 2 季'), findsOneWidget);
      expect(find.text('第 1 季'), findsOneWidget);
      expect(find.text('第 2 季'), findsOneWidget);

      await tester.tap(find.text('第 2 季'));
      await tester.pumpAndSettle();

      expect(selectedSeason?.id, dramaS2.id);
    });

    testWidgets('PlayerDesktopPanelView 渲染多季横栏并响应切季', (tester) async {
      const dramaS1 = Drama(
        id: 'd_s1',
        source: 'hongguo',
        title: '至尊战王',
      );
      const dramaS2 = Drama(
        id: 'd_s2',
        source: 'hongguo',
        title: '至尊战王 第二季',
      );

      final series = [
        const HongguoSeriesEntry(drama: dramaS1, season: 1, unit: '季'),
        const HongguoSeriesEntry(drama: dramaS2, season: 2, unit: '季'),
      ];

      Drama? selectedSeason;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: PlayerDesktopPanelView(
                episodes: List.generate(
                  5,
                  (i) => Episode({'id': 'ep_$i', 'title': '第${i + 1}集'}, i + 1),
                ),
                currentIndex: 0,
                seriesEntries: series,
                currentDramaId: dramaS1.id,
                onSelectEpisode: (_) {},
                onSeasonSelected: (d) => selectedSeason = d,
              ),
            ),
          ),
        ),
      );

      expect(find.text('系列多季'), findsOneWidget);
      expect(find.text('共 2 季'), findsOneWidget);

      await tester.tap(find.text('第 2 季'));
      await tester.pumpAndSettle();

      expect(selectedSeason?.id, dramaS2.id);
    });

    testWidgets('PlayerMobilePanelView 渲染多季横栏并响应切季', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = testStore(prefs);
      final repo = FixtureRepository();

      const dramaS1 = Drama(
        id: 'd_m1',
        source: 'hongguo',
        title: '都市医武战神',
      );
      const dramaS2 = Drama(
        id: 'd_m2',
        source: 'hongguo',
        title: '都市医武战神 第二季',
      );

      final series = [
        const HongguoSeriesEntry(drama: dramaS1, season: 1, unit: '季'),
        const HongguoSeriesEntry(drama: dramaS2, season: 2, unit: '季'),
      ];

      Drama? selectedSeason;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 380,
              height: 600,
              child: PlayerMobilePanelView(
                detail: DramaDetail(
                  dramaS1,
                  List.generate(
                    5,
                    (i) => Episode({'id': 'ep_$i', 'title': '第${i + 1}集'}, i + 1),
                  ),
                ),
                currentIndex: 0,
                store: store,
                repository: repo,
                seriesEntries: series,
                onSelectEpisode: (_) {},
                onSeasonSelected: (d) => selectedSeason = d,
              ),
            ),
          ),
        ),
      );

      expect(find.text('系列多季'), findsOneWidget);
      expect(find.text('共 2 季'), findsOneWidget);

      await tester.tap(find.text('第 2 季'));
      await tester.pumpAndSettle();

      expect(selectedSeason?.id, dramaS2.id);
    });
  });
}
