import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/download/download_picker.dart';
import 'package:THLRedLook/pages/downloads/downloads_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late NativeRepository repository;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = LocalStore(prefs);
    repository = NativeRepository(background: true);
    repository.access = store;
  });

  const testDrama = Drama(
    id: 'hongguo:test_drama_888',
    source: 'hongguo',
    title: '重生之都市神医',
    cover: 'https://test.example.com/cover.jpg',
  );

  final testEpisodes = [
    Episode({'id': 'ep_1', 'name': '第1集'}, 1),
    Episode({'id': 'ep_2', 'name': '第2集'}, 2),
    Episode({'id': 'ep_3', 'name': '第3集'}, 3),
  ];

  final testDetail = DramaDetail(testDrama, testEpisodes);

  group('视频下载 UI 自动化与核心链路测试', () {
    testWidgets('1. DownloadPicker 选集交互与加入下载自动化测试', (tester) async {
      DownloadSelection? submittedSelection;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const ValueKey('open-picker'),
                onPressed: () async {
                  submittedSelection = await showModalBottomSheet<DownloadSelection>(
                    context: context,
                    builder: (_) => DownloadPicker(
                      detail: testDetail,
                      preferences: store.downloadPreferences,
                    ),
                  );
                },
                child: const Text('打开选集'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 打开选集弹窗
      await tester.tap(find.byKey(const ValueKey('open-picker')));
      await tester.pumpAndSettle();

      // 验证标题与默认全选
      expect(find.text('重生之都市神医'), findsOneWidget);
      expect(find.text('已选 3'), findsOneWidget);

      // 自动化测试“取消全选”
      final clearFinder = find.widgetWithText(TextButton, '取消全选');
      expect(clearFinder, findsOneWidget);
      await tester.tap(clearFinder);
      await tester.pumpAndSettle();
      expect(find.text('已选 0'), findsOneWidget);

      // 自动化测试“全选”
      final selectAllFinder = find.widgetWithText(TextButton, '全选');
      expect(selectAllFinder, findsOneWidget);
      await tester.tap(selectAllFinder);
      await tester.pumpAndSettle();
      expect(find.text('已选 3'), findsOneWidget);

      // 点击加入下载按钮
      final enqueueBtnFinder = find.byKey(const ValueKey('enqueue-downloads'));
      expect(enqueueBtnFinder, findsOneWidget);
      await tester.tap(enqueueBtnFinder);
      await tester.pumpAndSettle();

      // 验证提交选集回调结果
      expect(submittedSelection, isNotNull);
      expect(submittedSelection!.episodes.length, 3);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('2. DownloadsScreen 下载任务状态渲染与消除“下载失败”验证', (tester) async {
      // 预先加入 2 集下载
      final added = await repository.enqueueDownloads(
        testDetail,
        [testEpisodes[0], testEpisodes[1]],
        quality: 720,
      );
      expect(added, 2);

      // 渲染 DownloadsScreen
      await tester.pumpWidget(
        MaterialApp(
          home: DownloadsScreen(
            repository: repository,
            store: store,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证标题展示
      expect(find.text('重生之都市神医'), findsOneWidget);

      // 关键核心断言：必须显示“2/2 集已下载”，绝不包含“失败”或“项失败”
      expect(find.textContaining('2/2 集已下载'), findsOneWidget);
      expect(find.textContaining('项失败'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('3. DownloadsScreen 展开合集、分集离线图标及本地文件完整性验证', (tester) async {
      // 预先加入任务
      await repository.enqueueDownloads(
        testDetail,
        [testEpisodes[0], testEpisodes[1]],
        quality: 1080,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DownloadsScreen(
            repository: repository,
            store: store,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 单合集时默认展开分集列表，应展示单集信息
      expect(find.text('第 1 集'), findsOneWidget);
      expect(find.text('第 2 集'), findsOneWidget);

      // 验证分集图标显示为已下载完成状态（不再是 error 失败图标）
      expect(find.byIcon(Icons.offline_pin_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.textContaining('已下载'), findsWidgets);

      // 验证本地播放端点与真实文件存在性
      final playbackPlan = await repository.localPlayback(testDrama, testEpisodes[0]);
      expect(playbackPlan, isNotNull);
      expect(playbackPlan!.local, isTrue);
      expect(playbackPlan.url, isNotEmpty);

      final file = File(playbackPlan.url);
      expect(file.existsSync(), isTrue, reason: '本地视频文件必须真实落地磁盘');
      expect(file.lengthSync(), greaterThan(0), reason: '本地视频文件大小必须大于0');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('4. 批量控制（全部暂停 / 全部继续）状态流转自动化测试', (tester) async {
      await repository.enqueueDownloads(
        testDetail,
        [testEpisodes[0]],
        quality: 720,
      );

      // 全部暂停
      await repository.controlDownloads('pauseAll');
      var jobs = await repository.downloads();
      expect(jobs.first.state, 'paused');
      expect(jobs.first.stateLabel, '已暂停');

      // 全部继续 / 恢复
      await repository.controlDownloads('resumeAll');
      jobs = await repository.downloads();
      expect(jobs.first.state, 'completed');
      expect(jobs.first.stateLabel, '已下载');
    });
  });
}
