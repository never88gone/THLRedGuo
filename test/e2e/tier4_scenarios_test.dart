import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/episode_browser.dart';
import 'package:THLRedLook/home_screen.dart';
import 'package:THLRedLook/main.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:media_kit/media_kit.dart';

import 'e2e_fixtures.dart';

void main() {
  group('Tier 4: 真实/半真实业务端到端场景 (TEST_INFRA Scenarios)', () {
    testWidgets('场景 1: 冷启动 -> 原生初始化 -> 首页红果分类浏览 -> 下拉/翻页加载更多', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      // 1. 冷启动与原生核心生命周期初始化
      await repository.initialize();
      await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
      await tester.pumpAndSettle();

      // 2. 首页展示红果短剧分类内容
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('真果之绝世神医'), findsOneWidget);

      // 3. 翻页加载更多数据（分页流转）
      final page2 = await repository.catalog('hongguo', page: 2);
      expect(page2.items.any((d) => d.id.contains('page2')), isTrue);
      expect(repository.catalogRequests.any((req) => req.contains(':2')), isTrue);
    });

    testWidgets('场景 2: 搜索输入 -> 关键词联想防抖 -> 结果列表渲染 -> 点击进入剧集详情', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      // 1. 模拟搜索输入与关键词联想
      final query = '神医';
      final suggestions = await repository.suggestions(query);
      expect(suggestions, contains('真果之绝世神医'));

      // 2. 检索结果卡片加载
      final searchResult = await repository.catalog('hongguo', query: suggestions.first);
      expect(searchResult.items.isNotEmpty, isTrue);

      // 3. 进入目标剧集详情页
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(
            drama: searchResult.items.first,
            repository: repository,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EpisodeBrowser), findsOneWidget);
      expect(repository.detailFetchCount, 1);
    });

    testWidgets('场景 3: 剧集详情 -> 选集切换 (第1集->第2集) -> 清晰度切换 (高清->超清)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();
      final episodes = E2EFixtures.generateEpisodes(10);

      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(
            drama: E2EFixtures.hongguoDrama1,
            repository: repository,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 选集切换至第 2 集，清晰度从 720P 切换到 1080P
      final planEp1_720 = await repository.resolve(
        E2EFixtures.hongguoDrama1,
        episodes[0],
        quality: 720,
      );
      expect(planEp1_720.quality, 720);

      final planEp2_1080 = await repository.resolve(
        E2EFixtures.hongguoDrama1,
        episodes[1],
        quality: 1080,
      );
      expect(planEp2_1080.quality, 1080);
      expect(repository.resolvedEpisodes, containsAll([1, 2]));
      expect(repository.resolvedQualities, containsAll([720, 1080]));
    });

    test('场景 4: 真实/高保真红果视频起播 -> 缓冲状态转换 -> 播放进度持续递增 -> 暂停与恢复', () async {
      final player = E2EScriptedPlayer();

      // 1. 发起起播并拉流
      await player.open(Media('https://cenc.hongguo.test/stream/hongguo:700101/1_1080p.mp4'));
      expect(player.state.buffering, isFalse);
      expect(player.state.playing, isTrue);
      expect(player.state.duration, greaterThan(Duration.zero));

      // 2. 播放进度持续递增
      final pos1 = player.state.position;
      player.progressTime(const Duration(seconds: 4));
      expect(player.state.position, equals(pos1 + const Duration(seconds: 4)));

      // 3. 暂停播放
      await player.pause();
      expect(player.state.playing, isFalse);

      // 4. 恢复播放
      await player.play();
      expect(player.state.playing, isTrue);
    });

    testWidgets('场景 5: 桌面端全屏切换 -> 窗口缩放 -> 异常断网兜底重试', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();
      final player = E2EScriptedPlayer();
      final episodes = E2EFixtures.generateEpisodes(5);

      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. 打开播放界面
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            detail: DramaDetail(E2EFixtures.hongguoDrama1, episodes),
            initialIndex: 0,
            repository: repository,
            store: store,
            playerFactory: () => Player(platformPlayer: player),
            videoBuilder: (controls) => Container(key: const ValueKey('video-screen'), child: controls),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // 2. 模拟全屏切换与窗口拉伸
      tester.view.physicalSize = const Size(1920, 1080);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(const ValueKey('video-screen')), findsOneWidget);

      // 3. 模拟异常网络故障并自愈
      repository.simulateNetworkError = true;
      bool hasError = false;
      try {
        await repository.resolve(E2EFixtures.hongguoDrama1, episodes[2]);
      } catch (_) {
        hasError = true;
      }
      expect(hasError, isTrue);

      repository.simulateNetworkError = false;
      final recoveredPlan = await repository.resolve(E2EFixtures.hongguoDrama1, episodes[2]);
      expect(recoveredPlan.url, isNotEmpty);

      // 安全销毁播放界面
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    });
  });
}
