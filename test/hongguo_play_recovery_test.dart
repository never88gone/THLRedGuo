import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  setUp(CatPawJsRuntime.resetDeviceSessionForTesting);
  final source = File('assets/sources/hongguo.js').readAsStringSync();
  const id = '7345678901234567000';
  const url = 'https://v5-reading-video.qznovelvod.com/synthetic.mp4';
  Future<CatPawPlayResult> resolve(
    List<String> variants,
    List<String> probes, {
    Set<String> rejected = const {},
  }) async {
    final client = MockClient((r) async {
      expect(r.method, 'HEAD');
      probes.add(r.url.toString());
      return http.Response(
        '',
        rejected.contains(r.url.toString()) ? 403 : 200,
        headers: {'content-type': 'video/mp4'},
      );
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init('''
${source.replaceFirst('const existingPlay = spider.play;', "const existingPlay = async function(){return {url:''};};")}
HongguoApp.fetchAppPlayUrl=async function(){return {variants:[${variants.map((v) => "{vid:'$id',quality:'720p',url:'$v'}").join(',')}]};};
''');
    return runtime.play(
      '',
      '7345678901234567100_$id',
      flags: [
        {'avoidUrl': url},
      ],
    );
  }

  test(
    'the only route is revalidated after a temporary player failure',
    () async {
      final probes = <String>[];
      final result = await resolve([url], probes);
      expect(result.url, url);
      expect(probes, [url]);
    },
  );
  test('an alternative route remains preferred', () async {
    const alternate = 'https://v5-reading-video.qznovelvod.com/alternate.mp4';
    final probes = <String>[];
    expect((await resolve([url, alternate], probes)).url, alternate);
    expect(probes, [alternate]);
  });
  test(
    'failed alternatives do not permanently exclude a now healthy route',
    () async {
      const alternate = 'https://v5-reading-video.qznovelvod.com/alternate.mp4';
      final probes = <String>[];
      expect(
        (await resolve([url, alternate], probes, rejected: {alternate})).url,
        url,
      );
      expect(probes, [alternate, url]);
    },
  );
  test('denied media keeps a useful error code and bounded probes', () async {
    final probes = <String>[];
    final result = await resolve([url], probes, rejected: {url});
    expect(result.url, isEmpty);
    expect(result.errorCode, 'MEDIA_HTTP_403');
    expect(probes.length, lessThanOrEqualTo(5));
  });

  for (final body in ['', ' \n\t']) {
    test(
      'empty model body is bounded and does not churn guest sessions ($body)',
      () async {
        var registrations = 0;
        var models = 0;
        final client = MockClient((request) async {
          if (request.url.path.contains('device_register')) {
            registrations++;
            return http.Response(
              jsonEncode({
                'device_id_str': '7345678901234567100',
                'install_id_str': '7345678901234567200',
              }),
              200,
            );
          }
          expect([
            '/novel/player/multi_video_model/v1/',
            '/novel/player/video_model/v1/',
          ], contains(request.url.path));
          models++;
          return http.Response(body, 200);
        });
        final runtime = CatPawJsRuntime(client, null, '合成空响应', false);
        addTearDown(runtime.dispose);
        addTearDown(client.close);
        await runtime.init(
          source.replaceFirst(
            'const existingPlay = spider.play;',
            "const existingPlay = async function(){return {url:''};};",
          ),
        );
        final result = await runtime.play('', '7345678901234567100_$id');
        expect(result.url, isEmpty);
        expect(result.errorCode, 'EMPTY_RESPONSE');
        expect(models, 4);
        expect(registrations, 1);
      },
    );
  }

  test('a decoding failure stops repeated model and guest requests', () async {
    final client = MockClient(
      (request) async => throw StateError('Unexpected HTTP request'),
    );
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init('''
${source.replaceFirst('const existingPlay = spider.play;', "const existingPlay = async function(){return {url:''};};")}
let modelCalls=0;
HongguoApp.fetchAppPlayUrl=async function(){modelCalls++;throw Object.assign(new Error('synthetic encoding'),{code:'RESPONSE_NOT_UTF8'});};
const originalPlay=spider.play;
spider.play=async function(...args){const result=await originalPlay(...args);if(modelCalls!==1)throw new Error('unbounded retry');return result;};
''');
    expect(
      (await runtime.play('', '7345678901234567100_$id')).errorCode,
      'RESPONSE_NOT_UTF8',
    );
    expect(
      CatPawSourceFailure.playback('EMPTY_RESPONSE').message,
      contains('没有返回播放数据'),
    );
    expect(
      CatPawSourceFailure.playback('RESPONSE_NOT_UTF8').message,
      contains('无法解码'),
    );
  });
}
