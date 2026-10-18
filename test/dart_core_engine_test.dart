import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';

void main() {
  group('DartCoreEngine 核心引擎与内置源调度自动化测试', () {
    late DartCoreEngine engine;
    late String hongguoScript;
    late Directory tempDir;

    setUpAll(() async {
      final jsFile = File('assets/sources/hongguo.js');
      expect(jsFile.existsSync(), isTrue);
      hongguoScript = await jsFile.readAsString();
      hongguoScript += r"""
globalThis.fetch = async function(url, options) {
  if (String(url).indexOf('/service/2/device_register/') >= 0) return {status:200,text:async()=>JSON.stringify({device_id_str:"7345678901234567001",install_id_str:"7345678901234567002"})};
  if (String(url).indexOf('/reading/bookapi/search/tab/v') >= 0) {
    const offset = /[?&]offset=(\d+)/.exec(String(url));
    const first = !offset || offset[1] === "0";
    return {status:200,text:async()=>JSON.stringify({code:0,search_tabs:[{tab_type:29,has_more:first,next_offset:first?10:20,passback:first?"opaque-next":"",search_id:"synthetic-search",data:[{video_data:[{series_id:first?"7345678901234567000":"7345678901234567001",title:"合成搜索结果"}]}]}]})};
  }
  if (String(url).indexOf('/novel/player/video_detail/v1/') >= 0) {
    return { status: 200, text: async function() {
      return JSON.stringify({ data: { video_data: {
        series_title: "合成引擎剧集",
        video_list: [{vid: "7345678901234568000"}, {vid: "7345678901234568001"}]
      } } });
    } };
  }
  return { status: 404, headers: {}, text: async function() { return ""; } };
};
""";

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

    test('搜索分页从源结果贯穿核心', () async {
      await engine.dispatch({
        'action': 'jsSource.load',
        'script': hongguoScript,
        'fileName': 'hongguo.js',
      });
      final first = await engine.dispatch({
        'action': 'catalog',
        'source': 'hongguo',
        'query': '合成搜索',
        'page': 1,
      });
      final second = await engine.dispatch({
        'action': 'catalog',
        'source': 'hongguo',
        'query': '合成搜索',
        'page': 2,
      });
      expect(first['data']['hasMore'], isTrue);
      expect(second['data']['hasMore'], isFalse);
      expect(second['data']['page'], 2);
      expect(
        first['data']['items'].first['id'],
        isNot(second['data']['items'].first['id']),
      );
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

    test('3. 分类获取 (categories) 与官方三类验证', () async {
      final catRes = await engine.dispatch({
        'action': 'categories',
        'source': 'hongguo',
      });
      expect(catRes['ok'], isTrue);
      final list = (catRes['data']['items'] as List);
      final ids = list.map((c) => c['id']).toList();
      final names = list.map((c) => c['name']).toList();

      expect(ids, containsAll(['real-drama', 'comic-drama', 'ai-drama']));
      expect(names, containsAll(['真人剧', '漫剧', 'AI剧']));
    });

    test('4. 榜单配置 (rankingBoards) 验证', () async {
      final boardRes = await engine.dispatch({'action': 'rankingBoards'});
      expect(boardRes['ok'], isTrue);
      final boards = (boardRes['data']['items'] as List);
      expect(boards.length, greaterThanOrEqualTo(3));

      final boardIds = boards.map((b) => b['id']).toList();
      expect(
        boardIds,
        containsAll(['hongguo-hot', 'hongguo-new', 'hongguo-search']),
      );
    });

    test('5. 缺少准确弹幕分集标识时明确返回不支持', () async {
      final result = await engine.dispatch({
        'action': 'danmaku',
        'dramaId': 'hongguo:7345678901234567890',
        'episode': 1,
      });
      expect(result['ok'], isFalse);
      expect(result['error'], contains('本集暂不支持弹幕'));
      expect(result.containsKey('data'), isFalse);
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
      expect(data['chapters'], hasLength(2));
      expect(data['chapters'][0]['raw'], contains('7345678901234568000'));
    });

    test('7. 播放解析 (resolve) 兜底与直链调度测试', () async {
      final input = {
        'action': 'resolve',
        'drama': {'id': 'hongguo:7345678901234567890', 'source': 'hongguo'},
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
      expect(
        playData['url'],
        equals('https://v9-dy-y.hongguoduanju.com/video/stream.m3u8'),
      );
      expect(playData['mimeType'], equals('application/x-mpegURL'));
      expect(playData['quality'], equals(0));
      expect(playData['qualities'], isEmpty);
      expect(playData['session'], contains('hongguo'));
      expect(playData['danmakuId'], isEmpty);
    });

    test('当前分集取流失败时不把网页或拼接地址作为视频返回', () async {
      final result = await engine.dispatch({
        'action': 'resolve',
        'drama': {'id': 'hongguo:7345678901234567890', 'source': 'hongguo'},
        'index': 2,
        'chapter': {
          'url':
              'https://hongguoduanju.com/player/7345678901234567890/7345678901234568001',
        },
      });
      expect(result['ok'], isFalse);
      expect(result['error'], contains('无法从数据源'));
    });

    test('8. 下载队列 (enqueueDownloads & control) 与本地播放测试', () async {
      final enqueueRes = await engine.dispatch({
        'action': 'enqueueDownloads',
        'drama': {'id': 'hongguo:7345678901234567890', 'title': '至尊天骄归来'},
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
        'jobIds': [
          'hongguo:7345678901234567890:1',
          'hongguo:7345678901234567890:2',
        ],
        'command': 'resume',
      });
      expect(batchCtrlRes['ok'], isTrue);
      expect((batchCtrlRes['data']['completed'] as List).length, equals(2));
    });
    test('JS 内容密钥和有效期完整传入播放方案', () async {
      final script =
          '''
var spider = {
  meta: { id: "hongguo", name: "合成密钥契约", version: "1.0.0", type: "video" },
  play: async function() {
    return { url: "https://media.example.test/encrypted.mp4", decryptionKey: "${'1' * 32}", expiresAt: 1800000000000, mediaBytes: 400000000, quality: 1080, header: { "X-Synthetic": "required" } };
  }
};
''';
      final installed = await engine.dispatch({
        'action': 'jsSource.saveAndLoad',
        'fileName': 'hongguo.js',
        'script': script,
      });
      expect(installed['ok'], isTrue);
      final result = await engine.dispatch({
        'action': 'resolve',
        'drama': {
          'id': 'hongguo:7345678901234567000',
          'source': 'hongguo',
          'sourceId': '7345678901234567000',
        },
        'chapter': {
          'raw':
              'https://hongguoduanju.com/player/7345678901234567000/7345678901234568000',
        },
        'index': 1,
      });
      expect(result['ok'], isTrue);
      expect(result['data']['decryptionKey'], '1' * 32);
      expect(result['data']['mediaBytes'], 400000000);
      expect(result['data']['expiresAt'], 1800000000000);
      expect(result['data']['headers']['X-Synthetic'], 'required');
      expect(result['data']['quality'], 1080);
    });
  });
}
