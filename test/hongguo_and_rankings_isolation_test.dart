import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/js_source_models.dart';
import 'package:THLRedLook/js_source_service.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/ranking_models.dart';
import 'package:THLRedLook/rankings_screen.dart';

import 'fixtures.dart';

class RankingsMockRepository extends FixtureRepository {
  final List<JsSourceMeta> mockSources = [
    const JsSourceMeta(id: 'hongguo', name: '红果免费短剧', version: '1.0.0', description: 'test'),
    const JsSourceMeta(id: 'yeguo', name: '野果短剧', version: '1.0.0', description: 'test'),
  ];
  String activeId = 'hongguo';

  @override
  Future<int> jsSourceScan() async => mockSources.length;

  @override
  Future<List<JsSourceMeta>> jsSourceList() async => mockSources;

  @override
  Future<String> jsSourceGetActive() async => activeId;

  @override
  Future<bool> jsSourceSetActive(String sourceId) async {
    activeId = sourceId;
    return true;
  }

  @override
  Future<List<RankingBoard>> rankingBoards() async {
    return const [
      RankingBoard(id: 'hongguo-hot', source: 'hongguo', name: '总热播榜'),
      RankingBoard(id: 'hongguo-real', source: 'hongguo', name: '真人剧榜'),
      RankingBoard(id: 'yeguo-recommend', source: 'yeguo', name: '野果目录榜'),
    ];
  }

  @override
  Future<RankingPage> rankings(String board, {int page = 1, bool force = false}) async {
    return RankingPage(
      items: [
        RankingItem(
          1,
          Drama(
            id: '$board:101',
            source: board.startsWith('hongguo') ? 'hongguo' : 'yeguo',
            title: board.startsWith('hongguo') ? '首辅娇娘' : '野果测试剧',
          ),
        ),
      ],
      page: 1,
      hasMore: false,
    );
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    return DramaDetail(drama, [
      Episode({'id': 'ep1', 'title': '第1集'}, 1),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('红果数据源与榜单隔离验证测试', () {
    late RankingsMockRepository repo;
    late LocalStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = testStore(prefs);
      repo = RankingsMockRepository();

      final service = JsSourceService(repo, prefs);
      await service.initialize();
      await service.switchSource('hongguo');
      await store.setCatalogSource('hongguo', allSources: false);
    });

    test('Drama.fromJson 鲁棒性验证：缺失或残缺 source 时能自动从 ID 或当前源补齐', () {
      // 1. 无 source 但有纯数字 ID
      final d1 = Drama.fromJson({'id': '7686713195246930968', 'title': '首辅娇娘'});
      expect(d1.source, equals('hongguo'));
      expect(d1.id, equals('hongguo:7686713195246930968'));
      expect(store.allowsSource(d1.source), isTrue);

      // 2. 有冒号前缀 ID 但 source 为空字符串
      final d2 = Drama.fromJson({'id': 'hongguo:12345', 'source': '', 'title': '二嫁有喜'});
      expect(d2.source, equals('hongguo'));
      expect(d2.sourceId, equals('12345'));
      expect(store.allowsSource(d2.source), isTrue);
    });

    testWidgets('DetailScreen 剧集详情授权验证：不误判为无权访问', (tester) async {
      final drama = Drama.fromJson({'id': 'hongguo:7686713195246930968', 'title': '首辅娇娘'});
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(
            repository: repo,
            store: store,
            drama: drama,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证未出现“当前用户无权访问”
      expect(find.text('当前用户无权访问'), findsNothing);
      expect(find.text('首辅娇娘'), findsWidgets);
    });

    testWidgets('RankingsScreen 榜单严格隔离验证：切换到红果后不展示野果榜单', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RankingsScreen(
            repository: repo,
            store: store,
            initialGroup: 'hongguo',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证当前展示的是红果榜单
      expect(find.textContaining('红果'), findsWidgets);
      expect(find.text('首辅娇娘'), findsOneWidget);

      // 验证完全不出现野果短剧榜单
      expect(find.text('野果目录榜'), findsNothing);
      expect(find.textContaining('野果'), findsNothing);
    });
  });
}
