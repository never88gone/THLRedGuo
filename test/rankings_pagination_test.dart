import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/ranking/ranking_models.dart';
import 'package:THLRedLook/pages/rankings/rankings_page.dart';

class _MockRankingsRepo extends AppRepository {
  final List<RankingBoard> mockBoards = [
    const RankingBoard(
      id: 'hongguo-app:all:ranklist_hot_sc',
      name: '推荐榜',
      description: '热门推荐榜单',
      source: 'hongguo',
    ),
  ];

  @override
  Future<List<RankingBoard>> rankingBoards() async {
    return mockBoards;
  }

  @override
  Future<RankingPage> rankings(
    String board, {
    int page = 1,
    bool force = false,
  }) async {
    if (page == 1) {
      // 模拟第 1 页：接口返回了局部 rank，甚至前两项都是 1
      return RankingPage(
        page: 1,
        hasMore: true,
        updatedText: '今日已更新',
        items: List.generate(
          10,
          (i) => RankingItem(
            i == 0 ? 1 : i, // 0 -> 1, 1 -> 1, 2 -> 2...
            Drama(
              id: 'hongguo:drama_${i + 1}',
              source: 'hongguo',
              sourceId: 'drama_${i + 1}',
              title: '剧集第${i + 1}名',
              cover: 'https://example.com/cover_${i + 1}.jpg',
              episodes: 80,
            ),
            metric: '热度 ${(10 - i) * 1000}',
          ),
        ),
      );
    } else {
      // 模拟第 2 页：真实接口返回的局部 rank 又重新从 1 开始计数
      return RankingPage(
        page: 2,
        hasMore: false,
        updatedText: '今日已更新',
        items: List.generate(
          10,
          (i) => RankingItem(
            i + 1, // 重新从 1 开始计数: 1, 2, ..., 10
            Drama(
              id: 'hongguo:drama_${i + 11}',
              source: 'hongguo',
              sourceId: 'drama_${i + 11}',
              title: '剧集第${i + 11}名',
              cover: 'https://example.com/cover_${i + 11}.jpg',
              episodes: 60,
            ),
            metric: '热度 ${(20 - (i + 10)) * 500}',
          ),
        ),
      );
    }
  }

  @override
  Future<String> cover(Drama drama, {bool force = false}) async {
    return '';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('排行榜翻页索引序号单调递增自动化验证', () {
    late LocalStore store;
    late _MockRankingsRepo repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = LocalStore(prefs);
      repo = _MockRankingsRepo();
    });

    testWidgets('排行榜加载更多到第 2 页时，索引序号严格单调递增，前面条目不被插队或错乱', (tester) async {
      // 设定为移动端宽度（< 600），并赋予足够高度，使翻页前后条目均在视口可见
      tester.view.physicalSize = const Size(500, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RankingsScreen(
              repository: repo,
              store: store,
              initialGroup: 'hongguo',
            ),
          ),
        ),
      );

      // 等待第 1 页加载完成
      await tester.pumpAndSettle();

      // 验证第 1 页展示的项：
      // 第 1 项为剧集第1名，第 2 项为剧集第2名
      expect(find.text('剧集第1名'), findsOneWidget);
      expect(find.text('剧集第2名'), findsOneWidget);

      // 验证在列表视图中序号从 1 严格连续递增到 3
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // 找到“加载更多”按钮并点击
      final loadMoreFinder = find.widgetWithText(OutlinedButton, '加载更多');
      expect(loadMoreFinder, findsOneWidget);
      await tester.tap(loadMoreFinder);

      // 等待第 2 页数据加载并渲染
      await tester.pumpAndSettle();

      // 核心断言 1：第 1 页的内容绝对没有被第二页的数据挤乱或排到后面
      // 第 1 项依然是剧集第1名且序号为 1
      expect(find.text('剧集第1名'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // 核心断言 2：第二页的数据追加在后，且序号顺接为 11, 12... 绝不重新从 1 开始
      expect(find.text('剧集第11名'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);

      // 验证全列表只有一个序号为 1 的短剧（绝不出现 1, 1, 2, 2 错乱）
      expect(find.text('1'), findsOneWidget);

      // 核心断言 3：切换视图模式到瀑布流视图，角标文案（TOP 1, TOP 2, TOP 3, #11 等）同样连续正确
      final toggleViewBtn = find.byKey(const ValueKey('toggle-ranking-view-mode'));
      expect(toggleViewBtn, findsOneWidget);
      await tester.tap(toggleViewBtn);
      await tester.pumpAndSettle();

      // 瀑布流模式下前三名为 TOP 1, TOP 2, TOP 3，第 11 名显示为 #11
      expect(find.text('TOP 1'), findsOneWidget);
      expect(find.text('TOP 2'), findsOneWidget);
      expect(find.text('TOP 3'), findsOneWidget);
      expect(find.text('#11'), findsOneWidget);
    });

    testWidgets('第 2 页包含重复条目时，去重后全局序号仍严格连续自增且不跳号', (tester) async {
      tester.view.physicalSize = const Size(500, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 自定义第 2 页包含第 1 页已有的 drama_10
      final duplicateRepo = _MockDuplicateRankingsRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RankingsScreen(
              repository: duplicateRepo,
              store: store,
              initialGroup: 'hongguo',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final loadMoreFinder = find.widgetWithText(OutlinedButton, '加载更多');
      expect(loadMoreFinder, findsOneWidget);
      await tester.tap(loadMoreFinder);
      await tester.pumpAndSettle();

      // 第 10 名依然是剧集第10名
      expect(find.text('剧集第10名'), findsOneWidget);
      // 第 2 页原本第一项为重复的剧集第10名，去重后下一个新条目为剧集第11名，序号紧接为 11
      expect(find.text('剧集第11名'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      // 确认剧集第12名序号为 12
      expect(find.text('剧集第12名'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });
  });
}

class _MockDuplicateRankingsRepo extends AppRepository {
  @override
  Future<List<RankingBoard>> rankingBoards() async {
    return const [
      RankingBoard(
        id: 'hongguo-app:all:ranklist_hot_sc',
        name: '推荐榜',
        description: '热门推荐榜单',
        source: 'hongguo',
      ),
    ];
  }

  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';

  @override
  Future<RankingPage> rankings(
    String board, {
    int page = 1,
    bool force = false,
  }) async {
    if (page == 1) {
      return RankingPage(
        page: 1,
        hasMore: true,
        items: List.generate(
          10,
          (i) => RankingItem(
            i + 1,
            Drama(
              id: 'hongguo:drama_${i + 1}',
              source: 'hongguo',
              sourceId: 'drama_${i + 1}',
              title: '剧集第${i + 1}名',
              cover: '',
              episodes: 80,
            ),
          ),
        ),
      );
    } else {
      // 第 2 页包含重复项 drama_10，以及新项 drama_11, drama_12
      return RankingPage(
        page: 2,
        hasMore: false,
        items: [
          RankingItem(
            1,
            const Drama(
              id: 'hongguo:drama_10',
              source: 'hongguo',
              sourceId: 'drama_10',
              title: '剧集第10名',
              cover: '',
              episodes: 80,
            ),
          ),
          RankingItem(
            2,
            const Drama(
              id: 'hongguo:drama_11',
              source: 'hongguo',
              sourceId: 'drama_11',
              title: '剧集第11名',
              cover: '',
              episodes: 60,
            ),
          ),
          RankingItem(
            3,
            const Drama(
              id: 'hongguo:drama_12',
              source: 'hongguo',
              sourceId: 'drama_12',
              title: '剧集第12名',
              cover: '',
              episodes: 60,
            ),
          ),
        ],
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
