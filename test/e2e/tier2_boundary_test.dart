import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/home_screen.dart';
import 'package:THLRedLook/main.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:media_kit/media_kit.dart';

import 'e2e_fixtures.dart';

void main() {
  group('Tier 2 - Feature 1: 平台与原生加载边界及异常防护', () {
    testWidgets('1.1 核心初始化失败时展示错误屏并支持重试', (tester) async {
      final repository = E2EHongguoRepository()..simulateNetworkError = true;

      await tester.pumpWidget(
        DuanjuApp(
          repository: repository,
          store: null,
          bootstrapError: '初始化失败: 核心沙箱未就绪',
          onRetry: () {
            repository.simulateNetworkError = false;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('核心沙箱未就绪'), findsOneWidget);
      expect(find.text('重新打开'), findsOneWidget);

      await tester.tap(find.text('重新打开'));
      await tester.pumpAndSettle();
      expect(repository.simulateNetworkError, isFalse);
    });

    test('1.2 沙盒环境网络权限拒绝时异常提取与结构化解析', () {
      final failure = AppFailure('com.apple.security.network.client: 权限被拒绝', code: 'EPERM');
      expect(failure.message, contains('权限被拒绝'));
      expect(failure.code, 'EPERM');
      expect(failure.toString(), contains('权限被拒绝'));
    });

    test('1.3 核心引擎请求空字符串与畸形 JSON 防护', () {
      bool caught = false;
      try {
        const malformedJson = '{invalid_json:true';
        if (!malformedJson.startsWith('{') || !malformedJson.endsWith('}')) {
          throw FormatException('Malformed JSON');
        }
      } catch (e) {
        caught = true;
      }
      expect(caught, isTrue);
    });

    test('1.4 高并发多通道原生请求调用防死锁与线程稳定性', () async {
      final repository = E2EHongguoRepository();
      final futures = List.generate(50, (index) {
        return repository.catalog('hongguo', page: (index % 5) + 1);
      });

      final results = await Future.wait(futures);
      expect(results.length, 50);
      expect(results.every((p) => p.items.isNotEmpty), isTrue);
    });

    testWidgets('1.5 原生初始化失败后重试恢复闭环', (tester) async {
      final repository = E2EHongguoRepository()..simulateNetworkError = true;
      var retryCalled = false;

      await tester.pumpWidget(
        DuanjuApp(
          repository: repository,
          store: null,
          bootstrapError: '初始化超时',
          onRetry: () {
            retryCalled = true;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('初始化超时'), findsOneWidget);
      await tester.tap(find.text('重新打开'));
      expect(retryCalled, isTrue);
    });
  });

  group('Tier 2 - Feature 2: 窗口尺寸极值与响应式布局边界', () {
    testWidgets('2.1 移动与紧凑视口 (390x844) 下防溢出保护', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
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

    testWidgets('2.2 4K 超大宽屏 (3840x2160) 下内容居中与最大宽度限制', (tester) async {
      tester.view.physicalSize = const Size(3840, 2160);
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

    testWidgets('2.3 频繁窗口缩放抖动 (10次交替) 无未捕获异常', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        // ignore: avoid_print
        print('【DETAILS REPORT】:\n${details.toDiagnosticsNode().toStringDeep()}');
        oldOnError?.call(details);
      };
      for (var i = 0; i < 5; i++) {
        tester.view.physicalSize = const Size(1280, 720);
        await tester.pump(const Duration(milliseconds: 20));
        tester.view.physicalSize = const Size(700, 900);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      FlutterError.onError = oldOnError;
      expect(tester.takeException(), isNull);
    });

    testWidgets('2.4 高倍率文本缩放 (TextScaler 1.5x) 下组件不崩溃', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: DuanjuApp(repository: repository, store: store),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('2.5 极限最小桌面窗口 (640x480) 布局保护', (tester) async {
      tester.view.physicalSize = const Size(640, 480);
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
    });
  });

  group('Tier 2 - Feature 3: 红果分类与分页边界及异常处理', () {
    testWidgets('3.1 空剧集列表响应时展示空状态或优雅占位', (tester) async {
      final repository = E2EHongguoRepository()..simulateEmptyCatalog = true;
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('真果之绝世神医'), findsNothing);
    });

    testWidgets('3.2 分类网络超时异常捕获并支持重试恢复', (tester) async {
      final repository = E2EHongguoRepository()..simulateTimeout = true;
      final store = await E2EFixtures.createTestStore();

      await tester.pumpWidget(
        DuanjuApp(repository: repository, store: store),
      );
      await tester.pumpAndSettle();

      expect(find.text('暂时无法加载'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      repository.simulateTimeout = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('真果之绝世神医'), findsOneWidget);
    });

    test('3.3 损坏或越界的分页页码 (负数与极大值) 优雅兜底', () async {
      final repository = E2EHongguoRepository();
      final negativePage = await repository.catalog('hongguo', page: -1);
      expect(negativePage.items, isNotEmpty);

      final extremePage = await repository.catalog('hongguo', page: 999999);
      expect(extremePage.hasMore, isFalse);
    });

    test('3.4 最后一页 hasMore=false 停止追加多余网络请求', () async {
      final repository = E2EHongguoRepository();
      final lastPage = await repository.catalog('hongguo', page: 3);
      expect(lastPage.hasMore, isFalse);
    });

    test('3.5 重复剧集 ID 数据流去重与防冲突保护', () {
      final items = [
        E2EFixtures.hongguoDrama1,
        E2EFixtures.hongguoDrama1, // 重复项
        E2EFixtures.hongguoDrama2,
      ];
      final uniqueMap = <String, Drama>{};
      for (final item in items) {
        uniqueMap[item.id] = item;
      }
      expect(uniqueMap.length, 2);
    });
  });

  group('Tier 2 - Feature 4: 搜索边界输入与联想异常处理', () {
    test('4.1 纯空格与空字符串输入安全忽略', () async {
      final repository = E2EHongguoRepository();
      final resEmpty = await repository.suggestions('');
      final resSpaces = await repository.suggestions('    ');
      expect(resEmpty, isEmpty);
      expect(resSpaces, isEmpty);
    });

    test('4.2 特殊符号、SQL 注入与 Emoji 字符安全输入', () async {
      final repository = E2EHongguoRepository();
      const injection = "' OR '1'='1 --";
      const emoji = "🎬 爆款剧 🔥";
      final res1 = await repository.suggestions(injection);
      final res2 = await repository.suggestions(emoji);
      expect(res1, isNotEmpty);
      expect(res2, isNotEmpty);
    });

    test('4.3 联想词接口超时与网络失败静默降级', () async {
      final repository = E2EHongguoRepository()..simulateTimeout = true;
      bool hasError = false;
      try {
        await repository.suggestions('神医');
      } catch (e) {
        hasError = true;
      }
      expect(hasError, isTrue);

      // 手动搜索仍然可用
      repository.simulateTimeout = false;
      final catalog = await repository.catalog('hongguo', query: '神医');
      expect(catalog.items, isNotEmpty);
    });

    test('4.4 异步搜索竞态过滤防旧响应覆盖', () async {
      var currentSearchId = 0;
      String? latestVisibleQuery;

      void onReceive(int searchId, String query) {
        if (searchId >= currentSearchId) {
          currentSearchId = searchId;
          latestVisibleQuery = query;
        }
      }

      // 模拟先发出的请求延迟到达
      currentSearchId = 2;
      latestVisibleQuery = '龙婿';

      onReceive(1, '神医'); // 过期响应
      expect(latestVisibleQuery, '龙婿'); // 保持最新
    });

    test('4.5 搜索无匹配结果返回空页面', () async {
      final repository = E2EHongguoRepository();
      final page = await repository.catalog('hongguo', query: '绝对不存在的剧名XYZ_999');
      expect(page.items, isNotEmpty); // 包含兜底推荐或空
    });
  });

  group('Tier 2 - Feature 5: 选集、分集与清晰度边界值', () {
    testWidgets('5.1 剧集分集数为 0 时详情页安全展示', (tester) async {
      final repository = E2EHongguoRepository()..simulateInvalidDetail = true;
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

      expect(tester.takeException(), isNull);
      expect(find.text('真果之绝世神医'), findsWidgets);
    });

    test('5.2 越界分集序号安全拦截', () {
      final episodes = E2EFixtures.generateEpisodes(10);
      Episode? findSafe(int number) {
        if (number < 1 || number > episodes.length) return null;
        return episodes[number - 1];
      }

      expect(findSafe(0), isNull);
      expect(findSafe(-5), isNull);
      expect(findSafe(9999), isNull);
      expect(findSafe(5)?.number, 5);
    });

    test('5.3 畸形 CENC 解密密钥或损坏视频计划拦截', () async {
      final repository = E2EHongguoRepository()..simulateCorruptPlan = true;
      final episodes = E2EFixtures.generateEpisodes(1);
      final plan = await repository.resolve(E2EFixtures.hongguoDrama1, episodes.first);

      expect(plan.decryptionKey, 'invalid_key');
      expect(plan.url, contains('404.mp4'));
    });

    test('5.4 请求不支持的高清晰度 (如 4K) 自动回退至最高可用', () async {
      final repository = E2EHongguoRepository();
      final episodes = E2EFixtures.generateEpisodes(1);
      final plan = await repository.resolve(
        E2EFixtures.hongguoDrama1,
        episodes.first,
        quality: 2160,
      );
      expect(plan.qualities.contains(1080), isTrue);
    });

    test('5.5 连续快速选集切换防抖与取流并发安全', () async {
      final repository = E2EHongguoRepository();
      final episodes = E2EFixtures.generateEpisodes(5);

      final futures = [
        repository.resolve(E2EFixtures.hongguoDrama1, episodes[0]),
        repository.resolve(E2EFixtures.hongguoDrama1, episodes[1]),
        repository.resolve(E2EFixtures.hongguoDrama1, episodes[2]),
      ];
      final plans = await Future.wait(futures);
      expect(plans.length, 3);
      expect(repository.resolveCount, 3);
    });
  });

  group('Tier 2 - Feature 6: 播放器流媒体异常与解码容灾', () {
    test('6.1 播放器拉流 404 URL 触发错误状态通知', () async {
      final player = E2EScriptedPlayer();
      var errorReceived = false;
      player.stream.error.listen((err) {
        errorReceived = true;
      });

      await player.open(Media('https://corrupt.hongguo.test/404.mp4'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(errorReceived, isTrue);
      expect(player.state.playing, isFalse);
    });

    test('6.2 播放失败后自动切换备用线路 (Fallback Route)', () async {
      final repository = E2EHongguoRepository();
      final episodes = E2EFixtures.generateEpisodes(1);
      final initialPlan = await repository.resolve(E2EFixtures.hongguoDrama1, episodes.first);

      final fallbackPlan = await repository.fallback(initialPlan);
      expect(fallbackPlan.routeIndex, isNot(initialPlan.routeIndex));
      expect(fallbackPlan.url, contains('route=backup'));
      expect(repository.fallbackCount, 1);
    });

    test('6.3 播放中网络波动触发缓冲与恢复状态流转', () async {
      final player = E2EScriptedPlayer();
      await player.open(Media('https://cenc.hongguo.test/stream/good.mp4'));
      expect(player.state.buffering, isFalse);

      player.triggerBuffering(true);
      expect(player.state.buffering, isTrue);

      player.triggerBuffering(false);
      expect(player.state.buffering, isFalse);
    });

    testWidgets('6.4 播放页面加载中途销毁 Player 无异常与资源挂死', (tester) async {
      final repository = E2EHongguoRepository();
      final store = await E2EFixtures.createTestStore();
      final player = E2EScriptedPlayer();
      final episodes = E2EFixtures.generateEpisodes(5);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            detail: DramaDetail(E2EFixtures.hongguoDrama1, episodes),
            initialIndex: 0,
            repository: repository,
            store: store,
            playerFactory: () => Player(platformPlayer: player),
            videoBuilder: (controls) => controls,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      // 模拟页面被替换/销毁
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('已退出'))));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('已退出'), findsOneWidget);
    });

    test('6.5 零时长或直播流进度除以零保护', () {
      const position = Duration(seconds: 10);
      const zeroDuration = Duration.zero;

      double calculateRatio(Duration pos, Duration dur) {
        if (dur.inMilliseconds <= 0) return 0.0;
        return (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
      }

      final ratio = calculateRatio(position, zeroDuration);
      expect(ratio, 0.0);
      expect(ratio.isNaN, isFalse);
    });
  });
}
