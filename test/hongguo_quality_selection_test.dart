import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/engine/dart_core_engine.dart';

void main() {
  final script = File('assets/sources/hongguo.js')
      .readAsStringSync()
      .replaceFirst(
        'const existingPlay = spider.play;',
        "const existingPlay = async function(){return {url:''};};",
      );
  const id = '7345678901234568456';
  setUp(CatPawJsRuntime.resetDeviceSessionForTesting);
  Map<String, dynamic> variant(
    int quality, {
    String codec = 'bytevc1',
    int? actual,
  }) => {
    'codec_type': codec,
    'definition': '${quality}p',
    'vwidth': actual ?? quality,
    'vheight': (actual ?? quality) * 16 ~/ 9,
    'main_url': base64Encode(
      utf8.encode(
        'https://fixture.qznovelvod.com/${codec}_${actual ?? quality}.mp4',
      ),
    ),
  };
  Future<CatPawPlayResult> resolve(
    List<Map<String, dynamic>> variants, {
    int requested = 0,
    Set<int> rejected = const {},
    List<String>? probes,
  }) async {
    final client = MockClient((request) async {
      if (request.url.path.contains('device_register')) {
        return http.Response(
          '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
          200,
        );
      }
      if (request.method == 'HEAD') {
        probes?.add(request.url.path);
        final rejectedQuality = rejected.any(
          (q) => request.url.path.endsWith('_$q.mp4'),
        );
        return http.Response(
          '',
          rejectedQuality ? 403 : 200,
          headers: {'content-type': 'video/mp4'},
        );
      }
      expect(request.url.path, '/novel/player/multi_video_model/v1/');
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            id: {
              'video_model': jsonEncode({
                'video_list': {
                  for (var i = 0; i < variants.length; i++) '$i': variants[i],
                },
              }),
            },
          },
        }),
        200,
      );
    });
    final runtime = CatPawJsRuntime(client, null, '合成清晰度', false);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    return runtime.play(
      '',
      '7345678901234567123_$id',
      flags: [
        {'quality': requested},
      ],
    );
  }

  test(
    'default chooses 1080 HEVC over 360 H264 and exposes every compatible quality',
    () async {
      final plan = await resolve([
        variant(360, codec: 'h264'),
        variant(720),
        variant(1080),
        variant(540),
      ]);
      expect(plan.quality, 1080);
      expect(plan.url, contains('bytevc1_1080.mp4'));
      expect(plan.qualities, [1080, 720, 540, 360]);
    },
  );
  test(
    'explicit lower quality is honored while retaining higher choices',
    () async {
      final plan = await resolve([
        variant(360),
        variant(720),
        variant(1080),
      ], requested: 720);
      expect(plan.quality, 720);
      expect(plan.url, contains('_720.mp4'));
      expect(plan.qualities, [1080, 720, 360]);
    },
  );
  test('1080 is preferred over 2160 when both are available', () async {
    expect(
      (await resolve([variant(2160), variant(1080), variant(720)])).quality,
      1080,
    );
  });
  test(
    'unavailable 1080 media falls back without reporting a false 1080 stream',
    () async {
      final probes = <String>[];
      final plan = await resolve(
        [variant(1080), variant(720), variant(360)],
        rejected: {1080},
        probes: probes,
      );
      expect(probes.first, contains('_1080.mp4'));
      expect(plan.quality, 720);
      expect(plan.url, contains('_720.mp4'));
    },
  );
  test(
    'higher-only media does not downgrade to 720 if 1080 is absent',
    () async {
      expect((await resolve([variant(2160), variant(720)])).quality, 2160);
    },
  );
  test('missing 1080 falls back to the best actual lower resolution', () async {
    final plan = await resolve([variant(540), variant(720), variant(360)]);
    expect(plan.quality, 720);
    expect(plan.qualities, [720, 540, 360]);
    expect(plan.qualities, isNot(contains(1080)));
  });
  test(
    'actual dimensions take precedence over a mislabeled quality field',
    () async {
      final plan = await resolve([variant(1080, actual: 540), variant(720)]);
      expect(plan.quality, 720);
      expect(plan.qualities, [720, 540]);
    },
  );
  test(
    'unsupported bytevc2 renditions never become selectable options',
    () async {
      final plan = await resolve([
        variant(1080, codec: 'bytevc2'),
        variant(720),
      ]);
      expect(plan.quality, 720);
      expect(plan.qualities, [720]);
    },
  );
  test(
    'Flutter engine forwards selected quality through resolve and preload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thl_quality_engine_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final engine = DartCoreEngine.instance;
      await engine.dispatch({
        'action': 'initialize',
        'directory': directory.path,
      });
      final loaded = await engine.dispatch({
        'action': 'jsSource.load',
        'fileName': 'hongguo.js',
        'script': """
const meta={id:'hongguo',name:'Synthetic',version:'1.0.0'};
const spider={play:async function(flag,id,flags){const quality=Number(flags.find(value=>'quality' in value)?.quality||0);return {url:'https://media.example.test/'+quality+'.mp4',quality:quality,qualities:[1080,720,360]};}};
""",
      });
      expect(loaded['ok'], true);
      for (final action in ['resolve', 'preload']) {
        final result = await engine.dispatch({
          'action': action,
          'source': 'hongguo',
          'drama': {'id': 'hongguo:7345678901234567123', 'source': 'hongguo'},
          'chapter': {'url': '7345678901234567123_7345678901234568456'},
          'index': 1,
          'quality': 720,
        });
        expect(result['ok'], true);
        expect(result['data']['quality'], 720);
        expect(result['data']['qualities'], [1080, 720, 360]);
      }
      await engine.dispatch({'action': 'cancelPlayback'});
    },
  );
  test(
    'Flutter detail recovery retains quality and failed CDN flags',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thl_quality_recovery_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final engine = DartCoreEngine.instance;
      await engine.dispatch({
        'action': 'initialize',
        'directory': directory.path,
      });
      final loaded = await engine.dispatch({
        'action': 'jsSource.load',
        'fileName': 'hongguo.js',
        'script': r"""
const meta={id:'hongguo',name:'Synthetic',version:'1.0.0'};
const spider={
 play:async function(flag,id,flags){
  if(String(id).endsWith('8456'))throw Object.assign(new Error('stale synthetic episode'),{code:'MISSING_EPISODE'});
  const quality=Number(flags.find(value=>'quality' in value)?.quality||0);
  const avoided=flags.find(value=>'avoidUrl' in value)?.avoidUrl;
  if(avoided!=='https://failed.example.test/old.mp4')throw new Error('missing failed CDN');
  return {url:'https://media.example.test/'+quality+'.mp4',quality,qualities:[1080,720,360]};
 },
 detail:async function(){return {list:[{vod_play_url:'第1集$7345678901234567123_7345678901234568002'}]};}
};
""",
      });
      expect(loaded['ok'], true);
      for (final action in ['resolve', 'preload']) {
        final result = await engine.dispatch({
          'action': action,
          'source': 'hongguo',
          'drama': {'id': 'hongguo:7345678901234567123', 'source': 'hongguo'},
          'chapter': {'url': '7345678901234567123_7345678901234568456'},
          'index': 1,
          'quality': 720,
          'avoidUrl': 'https://failed.example.test/old.mp4',
        });
        expect(result['ok'], true, reason: jsonEncode(result));
        expect(result['data']['quality'], 720);
        expect(result['data']['url'], 'https://media.example.test/720.mp4');
      }
      await engine.dispatch({'action': 'cancelPlayback'});
    },
  );
}
