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
                  submittedSelection =
                      await showModalBottomSheet<DownloadSelection>(
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

    test('2. 未接入传输时不能伪造下载成功或离线文件', () async {
      expect(repository.supportsDownloads, isFalse);
      await expectLater(
        repository.enqueueDownloads(testDetail, testEpisodes),
        throwsA(
          isA<AppFailure>().having(
            (error) => error.message,
            'message',
            contains('尚未实现'),
          ),
        ),
      );
      expect(await repository.downloads(), isEmpty);
    });
    testWidgets('3. Windows 下载入口明确显示尚未提供', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DownloadsScreen(repository: repository, store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前版本尚未提供下载'), findsOneWidget);
      expect(find.text('下载完成'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
    test('4. 暂停与继续不能伪造任务状态流转', () async {
      for (final command in ['pauseAll', 'resumeAll']) {
        await expectLater(
          repository.controlDownloads(command),
          throwsA(isA<AppFailure>()),
        );
        expect(await repository.downloads(), isEmpty);
      }
    });
  });
}
