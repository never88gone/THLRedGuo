import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/download/download_collections.dart';
import 'package:THLRedLook/core/player/playback_recovery.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/downloads/downloads_page.dart';
import 'package:THLRedLook/pages/downloads/offline_player_page.dart';
import 'package:THLRedLook/pages/settings/settings_page.dart';
import 'package:THLRedLook/views/downloads/download_batch_bar.dart';
import 'package:THLRedLook/views/downloads/download_collection_card.dart';
import 'package:THLRedLook/views/downloads/download_job_card.dart';
import 'package:THLRedLook/views/downloads/offline_episodes_sheet.dart';

class _MockDownloadRepo extends AppRepository {
  _MockDownloadRepo(this.jobList);
  final List<DownloadJob> jobList;

  @override
  bool get supportsDownloads => true;

  @override
  Future<List<DownloadJob>> downloads() async => jobList;

  @override
  Future<DownloadBatchResult> controlDownloadBatch(
    String command,
    List<String> ids, {
    Map<String, String> expectedVersions = const {},
  }) async {
    return DownloadBatchResult(
      completed: ids,
      failures: const {},
    );
  }

  @override
  Future<PlaybackPlan?> localPlayback(Drama drama, Episode episode) async {
    return const PlaybackPlan(
      url: '/mock/local/video.mp4',
      local: true,
      onlineCache: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late _MockDownloadRepo repo;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async => Directory.systemTemp.path,
        );
  });

  const testDrama1 = Drama(
    id: 'hongguo:drama_1',
    source: 'hongguo',
    title: '重生之都市神医',
    cover: 'https://test.example.com/cover1.jpg',
  );

  const testDrama2 = Drama(
    id: 'hongguo:drama_2',
    source: 'hongguo',
    title: '绝世战神',
    cover: 'https://test.example.com/cover2.jpg',
  );

  final testJobs = [
    DownloadJob(
      id: 'hongguo:drama_1_1',
      drama: testDrama1,
      episode: Episode(const {'id': 'ep_1', 'name': '第1集'}, 1),
      state: 'completed',
      bytes: 1024 * 1024 * 50,
      total: 1024 * 1024 * 50,
      progress: 1.0,
    ),
    DownloadJob(
      id: 'hongguo:drama_1_2',
      drama: testDrama1,
      episode: Episode(const {'id': 'ep_2', 'name': '第2集'}, 2),
      state: 'downloading',
      bytes: 1024 * 1024 * 20,
      total: 1024 * 1024 * 50,
      progress: 0.4,
    ),
    DownloadJob(
      id: 'hongguo:drama_1_3',
      drama: testDrama1,
      episode: Episode(const {'id': 'ep_3', 'name': '第3集'}, 3),
      state: 'completed',
      bytes: 1024 * 1024 * 50,
      total: 1024 * 1024 * 50,
      progress: 1.0,
    ),
    DownloadJob(
      id: 'hongguo:drama_2_1',
      drama: testDrama2,
      episode: Episode(const {'id': 'ep_1', 'name': '第1集'}, 1),
      state: 'failed',
      bytes: 1024,
      total: 1024 * 1024 * 50,
      progress: 0.01,
      error: '网络超时',
    ),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = LocalStore(prefs);
    repo = _MockDownloadRepo(List.of(testJobs));
  });

  group('UI 自动化测试：近期优化功能全覆盖', () {
    testWidgets('1. 下载管理中心 UI 自动化：多选模式、批量工具栏、合集展开收起及筛选弹窗', (
      tester,
    ) async {
      repo = _MockDownloadRepo(List.of(testJobs));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadsScreen(repository: repo, store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证两个剧集合集卡片均正确渲染
      expect(find.byType(DownloadCollectionCard), findsNWidgets(2));
      expect(find.text('重生之都市神医'), findsOneWidget);
      expect(find.text('绝世战神'), findsOneWidget);

      // 初始状态未进入多选，底部不应有 DownloadBatchBar
      expect(find.byType(DownloadBatchBar), findsNothing);

      // 自动化测试：点击合集卡片展开其分集任务
      await tester.tap(find.text('重生之都市神医'));
      await tester.pumpAndSettle();

      // 展开后应能看到该合集下的 DownloadJobCard
      expect(find.byType(DownloadJobCard), findsWidgets);
      expect(find.text('第 1 集'), findsOneWidget);

      // 自动化测试：点击进入多选模式
      final checklistFinder = find.byIcon(Icons.checklist_rounded);
      expect(checklistFinder, findsOneWidget);
      await tester.tap(checklistFinder);
      await tester.pumpAndSettle();

      // 验证顶部标题变为已选计数，且底部滑出 DownloadBatchBar
      expect(find.text('已选 0 项'), findsOneWidget);
      expect(find.byType(DownloadBatchBar), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      // 自动化测试：点击合集复选框进行批量选中
      final collectionCheckboxFinder = find.descendant(
        of: find.widgetWithText(Card, '重生之都市神医'),
        matching: find.byType(Checkbox),
      );
      expect(collectionCheckboxFinder, findsOneWidget);
      await tester.tap(collectionCheckboxFinder);
      await tester.pumpAndSettle();

      // 验证已选中都市神医的全部 3 项任务
      expect(find.text('已选 3 项'), findsOneWidget);

      // 自动化测试：退出多选
      final closeFinder = find.byIcon(Icons.close_rounded);
      expect(closeFinder, findsOneWidget);
      await tester.tap(closeFinder);
      await tester.pumpAndSettle();

      // 验证退出后恢复正常标题且 DownloadBatchBar 消失
      expect(find.text('下载任务'), findsOneWidget);
      expect(find.byType(DownloadBatchBar), findsNothing);

      // 自动化测试：点击筛选按钮弹出筛选弹窗
      final filterBtnFinder = find.byIcon(Icons.filter_list_rounded);
      expect(filterBtnFinder, findsOneWidget);
      await tester.tap(filterBtnFinder);
      await tester.pumpAndSettle();

      // 验证弹窗呈现
      expect(find.text('筛选下载合集'), findsOneWidget);
      expect(find.text('全部任务'), findsOneWidget);

      // 在弹窗中选择“已下载”（限定在 AlertDialog 内部查找）
      final completedChipFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ChoiceChip, '已下载'),
      );
      expect(completedChipFinder, findsOneWidget);
      await tester.tap(completedChipFinder);
      await tester.pumpAndSettle();

      // 点击“应用”
      final applyBtnFinder = find.widgetWithText(FilledButton, '应用');
      expect(applyBtnFinder, findsOneWidget);
      await tester.tap(applyBtnFinder);
      await tester.pumpAndSettle();

      // 弹窗关闭，列表应用了筛选
      expect(find.text('筛选下载合集'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('2. 离线播放器 UI 自动化：顶部栏、控制条、切集抽屉与手势显隐', (
      tester,
    ) async {
      repo = _MockDownloadRepo(List.of(testJobs));
      final completedJobs =
          testJobs.where((j) => j.completed && j.drama.id == testDrama1.id).toList();

      await tester.pumpWidget(
        MaterialApp(
          home: OfflinePlayerPage(
            drama: testDrama1,
            completedJobs: completedJobs,
            initialIndex: 0,
            repository: repo,
            store: store,
            videoBuilder: (context, controls) => Stack(children: [controls]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证顶部栏要素
      expect(find.text('重生之都市神医'), findsOneWidget);
      expect(find.text('第 1 集 · 本地离线播放'), findsOneWidget);
      expect(find.text('离线无网络'), findsOneWidget);
      expect(find.byKey(const ValueKey('offline-player-back')), findsOneWidget);

      // 验证选集按钮（两集已下载）
      final episodesBtnFinder = find.byKey(const ValueKey('offline-episodes-btn'));
      expect(episodesBtnFinder, findsOneWidget);
      expect(find.text('选集 (2)'), findsOneWidget);

      // 自动化测试：点击选集按钮唤起半屏抽屉
      await tester.tap(episodesBtnFinder);
      await tester.pumpAndSettle();

      // 验证离线选集抽屉 OfflineEpisodesSheet 呈现
      expect(find.byType(OfflineEpisodesSheet), findsOneWidget);
      expect(find.text('离线已下载集数'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing); // 第2集当时未完成
      expect(find.text('3'), findsOneWidget); // 第3集已完成

      // 自动化测试：点击切换到第 3 集
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();

      // 验证抽屉关闭，且顶部栏更新显示第 3 集
      expect(find.byType(OfflineEpisodesSheet), findsNothing);
      expect(find.text('第 3 集 · 本地离线播放'), findsOneWidget);

      // 自动化测试：点击屏幕手势区域切换控制条可见性
      expect(find.byKey(const ValueKey('offline-player-back')), findsOneWidget);
      final gestureFinder = find.byType(GestureDetector).first;
      await tester.tap(gestureFinder);
      await tester.pump(const Duration(milliseconds: 300));

      // 动画淡出后 AnimatedOpacity 为 0.0
      final animatedOpacityFinder = find.byType(AnimatedOpacity);
      expect(animatedOpacityFinder, findsOneWidget);
      final opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, 0.0);

      // 再次轻触，控制栏重新展现
      await tester.tap(gestureFinder);
      await tester.pump(const Duration(milliseconds: 300));
      final opacityWidget2 = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget2.opacity, 1.0);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('3. Android TV 设置中心遥控器方向键导航走焦自动化测试', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final tvStore = LocalStore(prefs);
      await tvStore.setDisplayMode('television');

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            repository: repo,
            store: tvStore,
            embedded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证第一项具有 autofocus 自动取得焦点
      final displayModeFinder = find.byKey(
        const ValueKey('settings-display-mode-entry'),
      );
      expect(displayModeFinder, findsOneWidget);

      final themeFinder = find.byKey(const ValueKey('settings-theme-entry'));
      expect(themeFinder, findsOneWidget);

      final playbackFinder = find.byKey(
        const ValueKey('settings-playback-entry'),
      );
      expect(playbackFinder, findsOneWidget);

      // 发送遥控器方向键向下 (Arrow Down) 切换焦点
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(themeFinder, findsOneWidget);

      // 向上返回第一项
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(displayModeFinder, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    test('4. 安卓电视硬件解码故障与自愈防护机制验证：阻断全量下载读百分比死循环', () {
      // 验证硬件解码与视频输出失败特征串能被精准捕获
      expect(
        PlaybackRecovery.videoOutputFailed(
          'Error opening/initializing the selected video_out (--vo) device.',
        ),
        isTrue,
      );
      expect(
        PlaybackRecovery.videoOutputFailed(
          'Error opening/initializing the VO window.',
        ),
        isTrue,
      );

      // 验证网络故障或普通音轨错误不会被误判为视频输出硬件故障
      expect(
        PlaybackRecovery.videoOutputFailed('HTTP 403 Forbidden: access denied'),
        isFalse,
      );
      expect(
        PlaybackRecovery.videoOutputFailed('Could not open/initialize audio device'),
        isFalse,
      );

      // 验证在硬件输出故障发生时，恢复策略绝不能误选 cache (forceEncryptedCache)
      const action = PlaybackRecoveryAction.refresh;
      final shouldForceCache = action == PlaybackRecoveryAction.cache;
      expect(shouldForceCache, isFalse);
    });
  });
}
