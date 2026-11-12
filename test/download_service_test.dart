import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late DartCoreEngine engine;
  late NativeRepository repository;
  late LocalStore store;

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

    sandbox = await Directory.systemTemp.createTemp('THL-download-service-');
    engine = DartCoreEngine.instance;
    await engine.dispatch({'action': 'initialize', 'directory': sandbox.path});
  });

  tearDown(() async {
    try {
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    } catch (_) {}
  });

  const testDrama = Drama(
    id: 'hongguo:download_test_1001',
    source: 'hongguo',
    title: '龙王殿前战神归来',
    cover: 'https://test.example.com/cover1001.jpg',
  );

  final testEpisodes = [
    Episode({'id': 'ep_1', 'name': '第1集'}, 1),
    Episode({'id': 'ep_2', 'name': '第2集'}, 2),
  ];

  final testDetail = DramaDetail(testDrama, testEpisodes);

  group('DownloadManager 与纯端侧下载全链路测试', () {
    test('1. supportsDownloads 顶层与底层开关一致为 true', () {
      expect(repository.supportsDownloads, isTrue);
    });

    test('2. 选集入队、重复入队自动跳过、任务列表查询', () async {
      final added = await repository.enqueueDownloads(testDetail, testEpisodes);
      expect(added, 2);

      final jobs = await repository.downloads();
      expect(jobs.length, 2);
      expect(jobs[0].drama.title, '龙王殿前战神归来');
      expect(jobs[0].episode.number, 1);
      expect(jobs[1].episode.number, 2);

      // 重复入队应自动跳过
      final addedAgain = await repository.enqueueDownloads(
        testDetail,
        testEpisodes,
      );
      expect(addedAgain, 0);
    });

    test('3. 存储查询与下载目录返回正常', () async {
      final storage = await repository.storage();
      expect(storage['directory'], isNotEmpty);
      expect(storage['usedBytes'], isNotNull);

      final dir = await repository.downloadDirectory();
      expect(dir, isNotEmpty);
    });

    test('4. 已下载媒体文件识别与 localPlayback 本地播放命中', () async {
      // 模拟已下载完成的视频文件在磁盘上落盘
      final downloadsDir = Directory(
        p.join(sandbox.path, 'pure_core', 'downloads'),
      );
      await downloadsDir.create(recursive: true);

      final cleanDramaDir = Directory(
        p.join(downloadsDir.path, 'hongguo_download_test_1001'),
      );
      await cleanDramaDir.create(recursive: true);

      final videoFile = File(p.join(cleanDramaDir.path, 'ep_1.mp4'));
      await videoFile.writeAsBytes(List.filled(1024, 0x42));

      // 未入队前查询 localPlayback
      final planDirect = await repository.localPlayback(
        testDrama,
        testEpisodes[0],
      );
      expect(planDirect, isNotNull);
      expect(planDirect!.local, isTrue);
      expect(planDirect.url, contains('ep_1.mp4'));

      // 入队已存在的文件应直接识别为已完成
      final added = await repository.enqueueDownloads(testDetail, [
        testEpisodes[0],
      ]);
      expect(added, 0);

      final jobs = await repository.downloads();
      final job = jobs.firstWhere(
        (j) => j.id == 'hongguo:download_test_1001_1',
      );
      expect(job.completed, isTrue);
      expect(job.bytes, 1024);
      expect(job.total, 1024);
      expect(job.progress, 1.0);

      // 未下载的分集查询 localPlayback 应返回 null
      final planNotDownloaded = await repository.localPlayback(
        testDrama,
        testEpisodes[1],
      );
      expect(planNotDownloaded, isNull);
    });

    test('5. 批量控制 controlDownloadBatch（pause, resume, remove）', () async {
      await repository.enqueueDownloads(testDetail, testEpisodes);
      final jobs = await repository.downloads();
      final ids = jobs.map((j) => j.id).toList();

      final pauseBatch = await repository.controlDownloadBatch('pause', ids);
      expect(pauseBatch.completed.length, ids.length);
      var afterPause = await repository.downloads();
      expect(afterPause.every((j) => j.state == 'paused'), isTrue);

      final resumeBatch = await repository.controlDownloadBatch('resume', ids);
      expect(resumeBatch.completed.length, ids.length);

      final removeBatch = await repository.controlDownloadBatch('remove', ids);
      expect(removeBatch.completed.length, ids.length);
      expect(await repository.downloads(), isEmpty);
    });
  });
}
