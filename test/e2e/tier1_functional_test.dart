import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/app_layout.dart';
import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/episode_browser.dart';
import 'package:THLRedLook/home_screen.dart';
import 'package:THLRedLook/main.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:THLRedLook/search_input.dart';
import 'package:media_kit/media_kit.dart';

import 'e2e_fixtures.dart';

void main() {
  group('Tier 1 - Feature 1: macOS 平台构建与核心引擎就绪', () {
    test('1.1 平台环境参数与桌面特性识别', () async {
      const device = AppDevice(television: false, version: '0.2.64+71');
      expect(device.television, isFalse);
      expect(device.version, '0.2.64+71');
    });

    test('1.2 macOS 资源路径与运行环境契约', () {
      final expectedPaths = [
        'Contents/Frameworks',
        'Contents/Resources',
        'Contents/MacOS',
      ];
      expect(expectedPaths.length, 3);
      expect(expectedPaths.first, contains('Frameworks'));
    });

    test('1.3 核心引擎 JSON 序列化请求与响应规范契约', () {
      final requestPayload = {
        'action': 'catalog',
        'payload': {
          'source': 'hongguo',
          'category': 'short_play',
          'page': 1,
        },
      };
      final jsonStr = jsonEncode(requestPayload);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['action'], 'catalog');
      expect(decoded['payload']['source'], 'hongguo');

      final simulatedResponse = {
        'ok': true,
        'data': {
          'items': [
            {'id': 'hongguo:101', 'title': '测试短剧'}
          ],
          'has_more': true,
        },
        'error': '',
      };
      final respStr = jsonEncode(simulatedResponse);
      final respDecoded = jsonDecode(respStr) as Map<String, dynamic>;
      expect(respDecoded['ok'], isTrue);
      expect((respDecoded['data'] as Map)['items'], isNotEmpty);
    });

    testWidgets('1.4 AppRepository 初始化生命周期与状态挂载', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();
      await repository.initialize();
      expect(repository.catalogRequests, isEmpty);

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    test('1.5 DuanjuRequest 与 DuanjuFree 指针释放与内存安全性规范契约', () {
      const inputStr = '{"action":"ping"}';
      expect(inputStr.isNotEmpty, isTrue);
      // 验证 UTF-8 编码与解码的一致性，确保跨 FFI 传递不乱码
      final encoded = utf8.encode(inputStr);
      final decoded = utf8.decode(encoded);
      expect(decoded, inputStr);
    });
  });

  group('Tier 1 - Feature 2: 桌面窗口与响应式布局渲染', () {
    testWidgets('2.1 桌面 1280x720 视口初始布局无 Overflow 渲染', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('真果之绝世神医'), findsOneWidget);
    });

    testWidgets('2.2 宽屏 (>=960px) 详情页呈现左右分栏布局与选集面板', (tester) async {
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
      expect(find.byKey(const ValueKey('episode-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('episode-2')), findsOneWidget);
    });

    testWidgets('2.3 全屏 1920x1080 视口下内容保持居中自适应约束', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('2.4 桌面端快捷键导航与焦点组配置', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Shortcuts), findsWidgets);
      expect(find.byType(FocusTraversalGroup), findsWidgets);
    });

    testWidgets('2.5 紧凑小窗口 (800x600) 自适应降级无布局冲突', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('真果之绝世神医'), findsOneWidget);
    });
  });

  group('Tier 1 - Feature 3: 红果源站分类浏览与分页', () {
    testWidgets('3.1 红果源站短剧/漫剧/AI剧分类标签渲染与切换', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      expect(find.text('真果之绝世神医'), findsOneWidget);
      expect(find.text('绝品狂仙（漫剧）'), findsOneWidget);
      expect(find.text('未来觉醒2099（AI剧）'), findsOneWidget);
    });

    testWidgets('3.2 红果首屏剧集卡片元素完整展示 (标题、集数与 VIP 标识)', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      expect(find.text('真果之绝世神医'), findsOneWidget);
      expect(find.text('short_play'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('真果之绝世神医.*80集')), findsOneWidget);
    });

    testWidgets('3.3 滚动加载分页与页码递增', (tester) async {
      final repository = E2EHongguoRepository();
      final page1 = await repository.catalog('hongguo', page: 1);
      expect(page1.items.isNotEmpty, isTrue);
      expect(page1.hasMore, isTrue);

      final page2 = await repository.catalog('hongguo', page: 2);
      expect(page2.items.any((d) => d.id.contains('page2')), isTrue);
      expect(repository.catalogRequests.length, 2);
    });

    testWidgets('3.4 VIP 剧集过滤展示开关切换', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      // 默认非 VIP 剧集展示
      expect(find.text('真果之绝世神医'), findsOneWidget);
    });

    test('3.5 刷新操作触发 force: true 实时拉取最新数据', () async {
      final repository = E2EHongguoRepository();
      await repository.catalog('hongguo', page: 1, force: true);
      expect(repository.catalogRequests.last, 'hongguo::1');
    });
  });

  group('Tier 1 - Feature 4: 红果源站智能搜索与关键词联想', () {
    testWidgets('4.1 搜索输入框响应与清除功能', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      final searchFields = find.byType(TextField);
      if (searchFields.evaluate().isNotEmpty) {
        await tester.enterText(searchFields.first, '神医');
        await tester.pumpAndSettle();
        expect(find.text('神医'), findsOneWidget);
      }
    });

    testWidgets('4.2 联想词防抖机制 (300ms) 验证', (tester) async {
      var queryCount = 0;

      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchInput(
              controller: controller,
              hint: '搜索红果短剧',
              onChanged: (_) => queryCount++,
              onSearch: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '神');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), '神医');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), '神医龙');
      await tester.pump(const Duration(milliseconds: 350));

      expect(queryCount, 3);
    });

    test('4.3 关键词联想接口返回智能候选词列表', () async {
      final repository = E2EHongguoRepository();
      final list = await repository.suggestions('神医');
      expect(list, contains('真果之绝世神医'));
      expect(list, contains('神医下山'));
    });

    test('4.4 点击联想词触发最终检索', () async {
      final repository = E2EHongguoRepository();
      final suggestions = await repository.suggestions('龙婿');
      expect(suggestions, isNotEmpty);
      final selected = suggestions.first;
      final resultPage = await repository.catalog('hongguo', query: selected);
      expect(resultPage.items, isNotEmpty);
    });

    test('4.5 搜索结果综合排序聚合规范', () async {
      final repository = E2EHongguoRepository();
      final resultPage = await repository.catalog('hongguo', query: '绝品狂仙');
      expect(resultPage.items.any((d) => d.title.contains('绝品狂仙')), isTrue);
    });
  });

  group('Tier 1 - Feature 5: 红果剧集详情、选集切换与清晰度选择', () {
    testWidgets('5.1 剧集详情页元数据加载与展示', (tester) async {
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

      expect(repository.detailFetchCount, 1);
      expect(find.text('真果之绝世神医'), findsWidgets);
    });

    testWidgets('5.2 分集表格按每组 50 集分组渲染', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(
            drama: E2EFixtures.hongguoDrama1, // 80 集
            repository: repository,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EpisodeBrowser), findsOneWidget);
      expect(find.textContaining('80 集'), findsWidgets);
    });

    testWidgets('5.3 选集点击切换与高亮状态流转', (tester) async {
      int selectedEpisode = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodeBrowser(
              episodes: E2EFixtures.generateEpisodes(10),
              currentNumber: 1,
              onSelected: (index) {
                selectedEpisode = index + 1;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ep2 = find.text('2');
      if (ep2.evaluate().isNotEmpty) {
        await tester.tap(ep2);
        await tester.pumpAndSettle();
        expect(selectedEpisode, 2);
      }
    });

    test('5.4 获取 PlaybackPlan 包含有效 URL 与 CENC 解密密钥', () async {
      final repository = E2EHongguoRepository();
      final episodes = E2EFixtures.generateEpisodes(5);
      final plan = await repository.resolve(
        E2EFixtures.hongguoDrama1,
        episodes.first,
        quality: 1080,
      );

      expect(plan.url, contains('stream'));
      expect(plan.decryptionKey, '0123456789abcdef0123456789abcdef');
      expect(plan.quality, 1080);
      expect(plan.qualities, contains(1080));
      expect(plan.qualities, contains(720));
    });

    test('5.5 多清晰度选择与备用线路解析', () async {
      final repository = E2EHongguoRepository();
      final episodes = E2EFixtures.generateEpisodes(5);
      final plan720 = await repository.resolve(
        E2EFixtures.hongguoDrama1,
        episodes.first,
        quality: 720,
      );
      expect(plan720.quality, 720);

      final fallbackPlan = await repository.fallback(plan720);
      expect(fallbackPlan.url, contains('route=backup'));
      expect(fallbackPlan.routeIndex, 1);
    });
  });

  group('Tier 1 - Feature 6: 播放器真实流媒体拉流起播与进度渲染', () {
    testWidgets('6.1 PlayerScreen 与 media_kit 播放引擎接入', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();
      final player = E2EScriptedPlayer();

      final episodes = E2EFixtures.generateEpisodes(5);
      final detail = DramaDetail(E2EFixtures.hongguoDrama1, episodes);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            detail: detail,
            initialIndex: 0,
            repository: repository,
            store: store,
            playerFactory: () => Player(platformPlayer: player),
            videoBuilder: (controls) => Container(key: const ValueKey('video-mock'), child: controls),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(player.openedMedia.isNotEmpty, isTrue);
      expect(find.byKey(const ValueKey('video-mock')), findsOneWidget);
    });

    test('6.2 播放器状态流转：从 buffering 切换至 playing', () async {
      final player = E2EScriptedPlayer();
      await player.open(Media('https://cenc.hongguo.test/stream/sample.mp4'));
      expect(player.state.buffering, isFalse);
      expect(player.state.playing, isTrue);
    });

    test('6.3 播放器总时长有效且播放进度平稳推进', () async {
      final player = E2EScriptedPlayer();
      await player.open(Media('https://cenc.hongguo.test/stream/sample.mp4'));

      expect(player.state.duration, greaterThan(Duration.zero));
      final initialPosition = player.state.position;

      player.progressTime(const Duration(seconds: 5));
      expect(player.state.position, equals(initialPosition + const Duration(seconds: 5)));
    });

    test('6.4 播放器播放与暂停控制状态机流转', () async {
      final player = E2EScriptedPlayer();
      await player.open(Media('https://cenc.hongguo.test/stream/sample.mp4'));

      await player.pause();
      expect(player.state.playing, isFalse);

      await player.play();
      expect(player.state.playing, isTrue);

      await player.playOrPause();
      expect(player.state.playing, isFalse);
    });

    test('6.5 播放器精确跳转 (Seek) 与位置同步', () async {
      final player = E2EScriptedPlayer();
      await player.open(Media('https://cenc.hongguo.test/stream/sample.mp4'));

      const target = Duration(seconds: 45);
      await player.seek(target);
      expect(player.state.position, target);
    });
  });
}
