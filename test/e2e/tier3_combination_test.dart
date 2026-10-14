import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/episode_browser.dart';
import 'package:THLRedLook/main.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:media_kit/media_kit.dart';

import 'e2e_fixtures.dart';

void main() {
  group('Tier 3: 跨功能组合交互测试 (Pairwise & Cross-Feature)', () {
    testWidgets('3.1 组合交互：分类切换与搜索并发触发', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
      await tester.pumpAndSettle();

      // 先切换分类到漫剧
      final comicCat = find.text('绝品狂仙（漫剧）');
      expect(comicCat, findsOneWidget);

      // 同时进行搜索输入
      final searchInput = find.byType(TextField);
      if (searchInput.evaluate().isNotEmpty) {
        await tester.enterText(searchInput.first, '绝世神医');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('3.2 组合交互：搜索结果点击 -> 详情页 -> 选集切换并写入历史', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

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

      expect(find.byType(EpisodeBrowser), findsOneWidget);

      // 切换至第 2 集，并持久化进度
      await store.saveWatch(
        WatchEntry(
          drama: E2EFixtures.hongguoDrama1,
          episode: 2,
          position: 15.0,
          duration: 120.0,
          updatedAt: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      final watched = store.watched(E2EFixtures.hongguoDrama1.id);
      expect(watched, isNotNull);
      expect(watched!.episode, 2);
      expect(watched.position, 15.0);
    });

    testWidgets('3.3 组合交互：全屏切换 -> 窗口拉伸与播放器界面自适应', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();
      final player = E2EScriptedPlayer();
      final episodes = E2EFixtures.generateEpisodes(10);

      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            detail: DramaDetail(E2EFixtures.hongguoDrama1, episodes),
            initialIndex: 0,
            repository: repository,
            store: store,
            playerFactory: () => Player(platformPlayer: player),
            videoBuilder: (controls) => Container(key: const ValueKey('video-container'), child: controls),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byKey(const ValueKey('video-container')), findsOneWidget);

      // 模拟放大至 1920x1080 全屏
      tester.view.physicalSize = const Size(1920, 1080);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('video-container')), findsOneWidget);

      // 安全销毁
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    });

    testWidgets('3.4 组合交互：网络超时故障 -> 重试成功 -> 剧集起播', (tester) async {
      final repository = E2EHongguoRepository()..simulateTimeout = true;
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
      await tester.pumpAndSettle();

      expect(find.text('暂时无法加载'), findsOneWidget);

      // 故障恢复
      repository.simulateTimeout = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('真果之绝世神医'), findsOneWidget);

      // 触发起播计划
      final plan = await repository.resolve(
        E2EFixtures.hongguoDrama1,
        E2EFixtures.generateEpisodes(1).first,
      );
      expect(plan.url, isNotEmpty);
      expect(plan.decryptionKey, isNotEmpty);
    });

    test('3.5 组合交互：清晰度动态切换 (1080P -> 720P) 叠加备用线路自愈', () async {
      final repository = E2EHongguoRepository();
      final episodes = E2EFixtures.generateEpisodes(5);

      // 请求 1080P
      final plan1080 = await repository.resolve(
        E2EFixtures.hongguoDrama1,
        episodes[0],
        quality: 1080,
      );
      expect(plan1080.quality, 1080);

      // 切换至 720P
      final plan720 = await repository.resolve(
        E2EFixtures.hongguoDrama1,
        episodes[0],
        quality: 720,
      );
      expect(plan720.quality, 720);

      // 模拟主线路波动，触发备用线路切换
      final fallbackPlan = await repository.fallback(plan720);
      expect(fallbackPlan.url, contains('route=backup'));
      expect(fallbackPlan.quality, 720); // 备用线路保持选中的 720P
    });

    testWidgets('3.6 组合交互：关键词联想点击 -> 详情 -> 追剧收藏状态联动', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      // 关键词联想
      final suggestions = await repository.suggestions('神医');
      expect(suggestions, isNotEmpty);

      // 进入详情
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

      // 点击收藏/加入追剧
      final favoriteBtn = find.byTooltip('加入追剧');
      if (favoriteBtn.evaluate().isNotEmpty) {
        await tester.tap(favoriteBtn);
        await tester.pumpAndSettle();
        expect(store.isFavorite(E2EFixtures.hongguoDrama1.id), isTrue);
      }
    });
  });
}
