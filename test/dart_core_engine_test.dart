import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:THLRedLook/core/engine/dart_core_engine.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/player/playback_diagnostics.dart';
import 'package:THLRedLook/core/player/playback_loader.dart';
import 'package:THLRedLook/core/player/playback_recovery.dart';
import 'package:THLRedLook/models/catalog/models.dart';

class _RecoveryRepository extends AppRepository {
  final pending = <String, Completer<PlaybackPlan>>{};
  final released = <String>[];
  int cancellations = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) => (pending[drama.id] ??= Completer<PlaybackPlan>()).future;
  @override
  Future<void> cancelPlayback() async {
    cancellations++;
  }

  @override
  Future<void> release(String session) async {
    released.add(session);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('切季播放恢复与 JS 响应解析回归', () {
    test('音频设备初始化失败必须恢复，不能仅以画面进度判定成功', () {
      expect(
        PlaybackRecovery.audioOutputFailed(
          'Could not open/initialize audio device -> no sound.',
        ),
        isTrue,
      );
      expect(
        PlaybackRecovery.audioOutputFailed(
          'COULD NOT OPEN/INITIALIZE AUDIO DEVICE',
        ),
        isTrue,
      );
      expect(
        PlaybackRecovery.audioOutputFailed('temporary network warning'),
        isFalse,
      );
      expect(PlaybackRecovery.audioOutputFailed(''), isFalse);
    });
    const encrypted = PlaybackPlan(
      url: 'https://synthetic.test/current.mp4',
      decryptionKey: '11111111111111111111111111111111',
      session: 'same-episode',
    );
    final episode = Episode({'id': 'synthetic-1'}, 1);
    const oldSeason = Drama(
      id: 'hongguo:synthetic-five',
      source: 'hongguo',
      title: '合成第五季',
    );
    const newSeason = Drama(
      id: 'hongguo:synthetic-four',
      source: 'hongguo',
      title: '合成第四季',
    );

    test('解密缓存使用当前准确分集，失败重试共用上限且不重复首轮缓存', () {
      final recovery = PlaybackRecovery();
      expect(
        recovery.next(encrypted, allowCache: true),
        PlaybackRecoveryAction.cache,
      );
      expect(recovery.cacheAttempted, isTrue);
      for (var i = 1; i < PlaybackRecovery.maxAttempts; i++) {
        expect(
          recovery.next(encrypted, allowCache: true),
          PlaybackRecoveryAction.refresh,
        );
        expect(recovery.retryDelay.inMilliseconds, inInclusiveRange(300, 1500));
      }
      expect(
        recovery.next(encrypted, allowCache: true),
        PlaybackRecoveryAction.stop,
      );
      recovery.reset();
      expect(recovery.cacheAttempted, isFalse);
      expect(
        recovery.next(encrypted, allowCache: true),
        PlaybackRecoveryAction.cache,
      );
    });

    test('未加密、本地或不支持缓存的播放器不选缓存恢复', () {
      for (final plan in [
        const PlaybackPlan(url: 'https://synthetic.test/plain.mp4'),
        const PlaybackPlan(
          url: '/synthetic/local.mp4',
          local: true,
          decryptionKey: '11111111111111111111111111111111',
        ),
      ]) {
        expect(
          PlaybackRecovery().next(plan, allowCache: true),
          PlaybackRecoveryAction.refresh,
        );
      }
      expect(
        PlaybackRecovery().next(encrypted),
        PlaybackRecoveryAction.refresh,
      );
    });

    test('旧季空闲加载器退出不取消新季的取流', () async {
      final repository = _RecoveryRepository();
      final previous = PlaybackLoader(repository);
      final next = PlaybackLoader(repository);
      final first = previous.load(oldSeason, episode);
      repository.pending[oldSeason.id]!.complete(encrypted);
      await first;
      final second = next.load(newSeason, episode);
      await previous.close();
      expect(repository.cancellations, 0);
      repository.pending[newSeason.id]!.complete(
        const PlaybackPlan(
          url: 'https://synthetic.test/new.mp4',
          session: 'new-season',
        ),
      );
      expect((await second)!.session, 'new-season');
      await next.close();
      expect(repository.cancellations, 0);
    });

    test('退出仍会取消自己的在途取流，并释放迟到会话', () async {
      final repository = _RecoveryRepository();
      final loader = PlaybackLoader(repository);
      final pending = loader.load(oldSeason, episode);
      await loader.close();
      expect(repository.cancellations, 1);
      repository.pending[oldSeason.id]!.complete(encrypted);
      expect(await pending, isNull);
      expect(repository.released, ['same-episode']);
    });

    test('快速换集忽略旧结果，保持最后一次请求', () async {
      final repository = _RecoveryRepository();
      final loader = PlaybackLoader(repository);
      final first = loader.load(oldSeason, episode);
      final second = loader.load(newSeason, episode);
      await Future<void>.delayed(Duration.zero);
      expect(repository.cancellations, 1);
      repository.pending[oldSeason.id]!.complete(encrypted);
      repository.pending[newSeason.id]!.complete(
        const PlaybackPlan(
          url: 'https://synthetic.test/new.mp4',
          session: 'new-season',
        ),
      );
      expect(await first, isNull);
      expect((await second)!.session, 'new-season');
      expect(repository.released, ['same-episode']);
      await loader.close();
    });

    test('没有错误码的站源失败也保留说明，诊断移除地址和凭据', () {
      final summary = playbackFailureSummary(
        AppFailure(
          '合成失败 https://synthetic.test/a.mp4?token=private access_token="synthetic-token" contentKey="11111111111111111111111111111111"\n请重试',
        ),
      );
      expect(summary, contains('source_error: 合成失败'));
      expect(summary, contains('请重试'));
      for (final value in [
        'https://',
        'synthetic-token',
        '11111111111111111111111111111111',
        '\n',
      ]) {
        expect(summary, isNot(contains(value)));
      }
    });

    test('长整数保护不改写字符串内的游标 JSON、转义引号和数字文本', () async {
      final runtime = CatPawJsRuntime();
      try {
        await runtime.init(r"""
var spider = {
  play: async function() {
    var text = String.raw`{"id":7695704804978330649,"nested":{"ids":[7688558312157088793,-7695704804978330649]},"passback":"{\"id\":7695704804978330649,\"list\":[7688558312157088793]}","description":"数字:7695704804978330649,数组[7688558312157088793]","escaped":"\\\"id:7695704804978330649,","fraction":123456789012345.5,"exponent":1.25e18}`;
    var parsed = JSON.parse(text);
    var revived = JSON.parse('{"id":7695704804978330649}', function(key,value){return key === 'id' ? 'revived:'+value : value;});
    var malformedRejected = false;
    try { JSON.parse('{"id":07695704804978330649}'); } catch(e) {malformedRejected=true;}
    return {url:'https://synthetic.test/video.mp4',header:{id:parsed.id,negative:parsed.nested.ids[1],array:parsed.nested.ids[0],passback:parsed.passback,description:parsed.description,escaped:parsed.escaped,fractionType:typeof parsed.fraction,exponentType:typeof parsed.exponent,revived:revived.id,malformed:String(malformedRejected)}};
  }
};
""");
        final result = await runtime.play('', 'synthetic');
        expect(result.header['id'], '7695704804978330649');
        expect(result.header['negative'], '-7695704804978330649');
        expect(result.header['array'], '7688558312157088793');
        expect(
          result.header['passback'],
          '{"id":7695704804978330649,"list":[7688558312157088793]}',
        );
        expect(
          result.header['description'],
          '数字:7695704804978330649,数组[7688558312157088793]',
        );
        expect(result.header['escaped'], contains('id:7695704804978330649,'));
        expect(result.header['fractionType'], 'number');
        expect(result.header['exponentType'], 'number');
        expect(result.header['revived'], 'revived:7695704804978330649');
        expect(result.header['malformed'], 'true');
      } finally {
        runtime.dispose();
      }
    });

    test('取消中的 JS 请求返回明确取消，新调用不继承取消状态', () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          started.complete();
          return response.future;
        }
        return http.Response('{}', 200);
      });
      final runtime = CatPawJsRuntime(client);
      try {
        await runtime.init(
          '''var spider={play:async function(){await fetch('https://synthetic.test/hold');return {url:'https://synthetic.test/video.mp4'};}};''',
        );
        final first = runtime.play('', 'synthetic');
        final failed = expectLater(
          first,
          throwsA(
            isA<CatPawSourceFailure>().having(
              (e) => e.code,
              'code',
              'cancelled',
            ),
          ),
        );
        await started.future;
        runtime.cancelPending();
        response.complete(http.Response('{}', 200));
        await failed;
        expect(
          (await runtime.play('', 'synthetic')).url,
          'https://synthetic.test/video.mp4',
        );
      } finally {
        runtime.dispose();
        client.close();
      }
    });
  });
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
  if (String(url).indexOf('/reading/bookapi/bookmall/tab/v') >= 0) {
    const names = {all:'全部',playlet:'真人剧',motion_comic:'漫剧',ai_playlet:'AI剧'};
    return {status:200,text:async()=>JSON.stringify({code:0,data:{tab_item:[{tab_type:8,cell_data:[{cell_id_str:'synthetic',cell_data:[],cell_selector:{outer_row:{items:Object.keys(names).map(id=>({selector_item_id:id,show_name:names[id],is_selected:id==='all'}))}}}]}]}})};
  }
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

    test('3. 分类获取 (categories) 与官方找剧四分类验证', () async {
      await engine.dispatch({
        'action': 'jsSource.load',
        'script': hongguoScript,
        'fileName': 'hongguo.js',
      });
      final catRes = await engine.dispatch({
        'action': 'categories',
        'source': 'hongguo',
      });
      expect(catRes['ok'], isTrue);
      final list = (catRes['data']['items'] as List);
      final ids = list.map((c) => c['id']).toList();
      final names = list.map((c) => c['name']).toList();

      expect(ids, [
        'app:discover:all',
        'app:discover:playlet',
        'app:discover:motion_comic',
        'app:discover:ai_playlet',
      ]);
      expect(names, ['全部', '真人剧', '漫剧', 'AI剧']);
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
      expect(result['error'], contains('站源暂未返回本集可播放地址'));
      expect(result['code'], 'HTTP_404');
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
    test('取流失败保留源错误码，拒绝结果不被合并为空错误', () async {
      await engine.dispatch({
        'action': 'jsSource.load',
        'fileName': 'hongguo.js',
        'script':
            "$hongguoScript\nspider.play=async function(){return {url:'',error:'MEDIA_REJECTED'};};",
      });
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
      expect(result['ok'], isFalse);
      expect(result['code'], 'MEDIA_REJECTED');
      expect(result['error'], contains('本集媒体地址暂不可用'));
    });
  });
}
