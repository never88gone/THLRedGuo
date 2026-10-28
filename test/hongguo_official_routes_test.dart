import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  final source = File('assets/sources/hongguo.js')
      .readAsStringSync()
      .replaceFirst(
        'const existingPlay = spider.play;',
        "const existingPlay = async function(){return {url:''};};",
      );
  const primary = 'api5-normal-sinfonlineb.fqnovel.com';
  const reading = 'reading.snssdk.com';
  const id = '7345678901234568456';
  const next = '7345678901234568457';
  const media = 'https://fixture.qznovelvod.com/route.mp4';
  setUp(CatPawJsRuntime.resetDeviceSessionForTesting);
  http.Response model(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final single = request.url.path == '/novel/player/video_model/v1/';
    final videoId = single
        ? body['video_id']
        : body['mixed_video_id_map']['1004'][0];
    expect(body['biz_param']['video_platform'], 1024);
    if (single) expect(body['content_type'], 1);
    expect(request.headers.keys, contains('x-medusa'));
    final entry = {
      'video_model': jsonEncode({
        'video_list': {
          'main': {
            'codec_type': 'h264',
            'definition': '720p',
            'vwidth': 720,
            'vheight': 1280,
            'main_url': base64Encode(utf8.encode(media)),
          },
        },
      }),
    };
    return http.Response(
      jsonEncode({
        'code': 0,
        'data': single ? entry : {videoId: entry},
      }),
      200,
    );
  }

  Future<CatPawJsRuntime> runtime(
    Future<http.Response> Function(http.Request) handler,
    List<String> calls,
    List<int> registrations,
  ) async {
    final client = MockClient((r) async {
      if (r.url.path.contains('device_register')) {
        registrations[0]++;
        return http.Response(
          '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
          200,
        );
      }
      if (r.method == 'HEAD') {
        return http.Response('', 200, headers: {'content-type': 'video/mp4'});
      }
      calls.add('${r.url.host}${r.url.path}');
      return handler(r);
    });
    final value = CatPawJsRuntime(client, null, '合成官方切换', false);
    addTearDown(value.dispose);
    addTearDown(client.close);
    await value.init(source);
    return value;
  }

  test(
    'empty primary uses official reading host and remembers it for next episode',
    () async {
      final calls = <String>[];
      final registrations = [0];
      final r = await runtime(
        (q) async => q.url.host == primary ? http.Response('', 200) : model(q),
        calls,
        registrations,
      );
      expect((await r.play('', '7345678901234567123_$id')).url, media);
      expect((await r.play('', '7345678901234567123_$next')).url, media);
      expect(calls.map((c) => c.split('/').first), [primary, reading, reading]);
      expect(registrations.single, 1);
    },
  );
  test(
    'signed single-video endpoint recovers when both batch endpoints return empty',
    () async {
      final calls = <String>[];
      final registrations = [0];
      final r = await runtime(
        (q) async => q.url.path.contains('multi_video_model')
            ? http.Response('', 200)
            : model(q),
        calls,
        registrations,
      );
      expect((await r.play('', '7345678901234567123_$id')).url, media);
      expect((await r.play('', '7345678901234567123_$next')).url, media);
      expect(calls, [
        '$primary/novel/player/multi_video_model/v1/',
        '$reading/novel/player/multi_video_model/v1/',
        '$reading/novel/player/video_model/v1/',
        '$reading/novel/player/video_model/v1/',
      ]);
      expect(registrations.single, 1);
    },
  );
  test(
    'all official routes failing remain bounded without renewing the guest',
    () async {
      final calls = <String>[];
      final registrations = [0];
      final r = await runtime(
        (q) async => http.Response('', 200),
        calls,
        registrations,
      );
      final plan = await r.play('', '7345678901234567123_$id');
      expect(plan.url, isEmpty);
      expect(plan.errorCode, 'EMPTY_RESPONSE');
      expect(calls, [
        '$primary/novel/player/multi_video_model/v1/',
        '$reading/novel/player/multi_video_model/v1/',
        '$reading/novel/player/video_model/v1/',
        'api5-normal.fqnovel.com/novel/player/multi_video_model/v1/',
      ]);
      expect(registrations.single, 1);
    },
  );
  for (final status in [403, 429]) {
    test('HTTP $status does not fan out across official hosts', () async {
      final calls = <String>[];
      final registrations = [0];
      final r = await runtime(
        (q) async => http.Response('', status),
        calls,
        registrations,
      );
      expect(
        (await r.play('', '7345678901234567123_$id')).errorCode,
        'HTTP_$status',
      );
      expect(calls, hasLength(1));
      expect(registrations.single, 1);
    });
  }
  test('business denial is retained without probing other endpoints', () async {
    final calls = <String>[];
    final registrations = [0];
    final r = await runtime(
      (q) async => http.Response('{"code":403,"data":{}}', 200),
      calls,
      registrations,
    );
    expect(
      (await r.play('', '7345678901234567123_$id')).errorCode,
      'BUSINESS_REJECTED',
    );
    expect(calls, hasLength(1));
    expect(registrations.single, 1);
  });
  test(
    'a failed remembered route can return to a healthy primary route',
    () async {
      final calls = <String>[];
      final registrations = [0];
      var primaryCalls = 0;
      var readingCalls = 0;
      final r = await runtime(
        (q) async {
          if (q.url.host == primary && ++primaryCalls == 1) {
            return http.Response('', 200);
          }
          if (q.url.host == reading && ++readingCalls == 2) {
            return http.Response('', 200);
          }
          return model(q);
        },
        calls,
        registrations,
      );
      expect((await r.play('', '7345678901234567123_$id')).url, media);
      expect((await r.play('', '7345678901234567123_$next')).url, media);
      expect(calls.map((c) => c.split('/').first), [
        primary,
        reading,
        reading,
        primary,
      ]);
      expect(registrations.single, 1);
    },
  );
  test(
    'missing selected episode cannot be replaced by a different episode',
    () async {
      final calls = <String>[];
      final registrations = [0];
      final r = await runtime(
        (q) async => http.Response(
          '{"code":0,"data":{"unrelated":{"video_model":"{}"}}}',
          200,
        ),
        calls,
        registrations,
      );
      expect(
        (await r.play('', '7345678901234567123_$id')).errorCode,
        'MISSING_MODEL',
      );
      expect(calls, hasLength(1));
    },
  );
}
