import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/dart_core_engine.dart';

void main() {
  group('DartCoreEngine 核心引擎与内置源调度自动化测试', () {
    late DartCoreEngine engine;
    late String hongguoScript;
    late Directory tempDir;

    setUpAll(() async {
      final jsFile = File('assets/sources/hongguo.js');
      expect(jsFile.existsSync(), isTrue);
      hongguoScript = await jsFile.readAsString();

      tempDir = await Directory.systemTemp.createTemp('thl_engine_test_');
      engine = DartCoreEngine.instance;

      final initRes = await engine.dispatch({
        'action': 'initialize',
        'directory': tempDir.path,
      });
      expect(initRes['ok'], isTrue);
    });

    tearDownAll(() async {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('1. 引擎初始化状态与环境配置验证', () async {
      expect(engine.isInitialized, isTrue);

      final settingsRes = await engine.dispatch({'action': 'resourceSettings'});
      expect(settingsRes['ok'], isTrue);
      expect(settingsRes['data']['concurrency'], equals(3));
      expect(settingsRes['data']['intervalMs'], equals(250));

      final saveRes = await engine.dispatch({
        'action': 'saveResourceSettings',
        'settings': {'concurrency': 5, 'intervalMs': 300},
      });
      expect(saveRes['ok'], isTrue);
      expect(saveRes['data']['concurrency'], equals(5));
      expect(saveRes['data']['intervalMs'], equals(300));
    });

    test('2. 载入并安装官方数据源插件 (jsSource.saveAndLoad & setActive)', () async {
      final loadRes = await engine.dispatch({
        'action': 'jsSource.saveAndLoad',
        'script': hongguoScript,
        'fileName': 'hongguo.js',
      });
      expect(loadRes['ok'], isTrue);
      expect(loadRes['data']['meta']['id'], equals('hongguo'));
      expect(loadRes['data']['meta']['name'], equals('官方免费短剧'));

      final listRes = await engine.dispatch({'action': 'jsSource.list'});
      expect(listRes['ok'], isTrue);
      final items = (listRes['data']['items'] as List);
      expect(items.any((item) => item['id'] == 'hongguo'), isTrue);

      final setActiveRes = await engine.dispatch({
        'action': 'jsSource.setActive',
        'source': 'hongguo',
      });
      expect(setActiveRes['ok'], isTrue);
      expect(setActiveRes['data']['active'], equals('hongguo'));

      final activeRes = await engine.dispatch({'action': 'jsSource.getActive'});
      expect(activeRes['ok'], isTrue);
      expect(activeRes['data']['active'], equals('hongguo'));
    });

    test('3. 分类获取 (categories) 与官方四大分类验证', () async {
      final catRes = await engine.dispatch({
        'action': 'categories',
        'source': 'hongguo',
      });
      expect(catRes['ok'], isTrue);
      final list = (catRes['data']['items'] as List);
      final ids = list.map((c) => c['id']).toList();
      final names = list.map((c) => c['name']).toList();

      expect(ids, containsAll(['real-drama', 'comic-drama', 'ai-drama', 'comic']));
      expect(names, containsAll(['真人剧', '漫剧', 'AI剧', '动漫']));
    });

    test('4. 榜单配置 (rankingBoards) 验证', () async {
      final boardRes = await engine.dispatch({'action': 'rankingBoards'});
      expect(boardRes['ok'], isTrue);
      final boards = (boardRes['data']['items'] as List);
      expect(boards.length, greaterThanOrEqualTo(3));

      final boardIds = boards.map((b) => b['id']).toList();
      expect(boardIds, containsAll(['hongguo-hot', 'hongguo-new', 'hongguo-search']));
    });

    test('5. 弹幕数据 (danmaku) 返回验证', () async {
      final danmakuRes = await engine.dispatch({
        'action': 'danmaku',
        'dramaId': 'hongguo:7345678901234567890',
        'episode': 1,
      });
      expect(danmakuRes['ok'], isTrue);
      final items = (danmakuRes['data']['items'] as List);
      expect(items, isNotEmpty);
      expect(items.first.containsKey('timeMs'), isTrue);
      expect(items.first.containsKey('text'), isTrue);
      expect(items.first.containsKey('color'), isTrue);
    });

    test('6. 剧集详情 (detail) 与多集章节解析验证', () async {
      // 模拟包含 vod_play_url 的详情
      final inputDrama = {
        'id': 'hongguo:7345678901234567890',
        'source': 'hongguo',
        'sourceId': '7345678901234567890',
        'title': '至尊天骄归来',
        'cover': 'https://p3.example.com/cover.jpg',
      };

      final detailRes = await engine.dispatch({
        'action': 'detail',
        'drama': inputDrama,
      });
      expect(detailRes['ok'], isTrue);
      final data = detailRes['data'];
      expect(data['drama']['source'], equals('hongguo'));
      expect(data['drama']['sourceId'], equals('7345678901234567890'));
      expect(data.containsKey('chapters'), isTrue);
    });

    test('7. 播放解析 (resolve) 兜底与直链调度测试', () async {
      final input = {
        'action': 'resolve',
        'drama': {
          'id': 'hongguo:7345678901234567890',
          'source': 'hongguo',
        },
        'index': 1,
        'chapter': {
          'url': 'https://v9-dy-y.hongguoduanju.com/video/stream.m3u8',
          'raw': 'https://v9-dy-y.hongguoduanju.com/video/stream.m3u8',
        },
        'quality': 1080,
      };

      final resolveRes = await engine.dispatch(input);
      expect(resolveRes['ok'], isTrue);
      final playData = resolveRes['data'];
      expect(playData['url'], equals('https://v9-dy-y.hongguoduanju.com/video/stream.m3u8'));
      expect(playData['mimeType'], equals('application/x-mpegURL'));
      expect(playData['quality'], equals(1080));
      expect(playData['session'], contains('hongguo'));
      expect(playData['danmakuId'], equals('hongguo:7345678901234567890:1'));
    });

    test('8. 下载队列 (enqueueDownloads & control) 与本地播放测试', () async {
      final enqueueRes = await engine.dispatch({
        'action': 'enqueueDownloads',
        'drama': {
          'id': 'hongguo:7345678901234567890',
          'title': '至尊天骄归来',
        },
        'entries': [
          {'index': 1, 'title': '第1集'},
          {'index': 2, 'title': '第2集'},
        ],
        'quality': 720,
      });
      expect(enqueueRes['ok'], isTrue);
      expect(enqueueRes['data']['added'], equals(2));

      // 验证下载列表
      final downloadsRes = await engine.dispatch({'action': 'downloads'});
      expect(downloadsRes['ok'], isTrue);
      final jobs = (downloadsRes['data']['jobs'] as List);
      expect(jobs.length, equals(2));

      // 控制命令暂停/恢复
      final ctrlRes = await engine.dispatch({
        'action': 'controlDownloads',
        'jobId': 'hongguo:7345678901234567890:1',
        'command': 'pause',
      });
      expect(ctrlRes['ok'], isTrue);

      // 批量控制命令
      final batchCtrlRes = await engine.dispatch({
        'action': 'controlDownloadBatch',
        'jobIds': ['hongguo:7345678901234567890:1', 'hongguo:7345678901234567890:2'],
        'command': 'resume',
      });
      expect(batchCtrlRes['ok'], isTrue);
      expect((batchCtrlRes['data']['completed'] as List).length, equals(2));
    });
  });
}
