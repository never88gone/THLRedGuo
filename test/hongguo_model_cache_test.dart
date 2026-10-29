import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  const firstId = '7345678901234568001';
  const secondId = '7345678901234568002';
  final source = File('assets/sources/hongguo.js').readAsStringSync();
  setUp(CatPawJsRuntime.resetDeviceSessionForTesting);

  Future<
    ({
      Future<CatPawPlayResult> Function(
        String, {
        int quality,
        int advance,
        String avoidUrl,
        bool reset,
      })
      play,
      int Function() models,
      int Function() registrations,
    })
  >
  fixture({int? validity = 21600000, bool rejectFirstMedia = false}) async {
    var models = 0, registrations = 0;
    var now = DateTime.now().millisecondsSinceEpoch;
    final client = MockClient((request) async {
      if (request.url.path.contains('device_register')) {
        registrations++;
        return http.Response(
          jsonEncode({
            'device_id_str': '7345678901234567100',
            'install_id_str': '7345678901234567${200 + registrations}',
          }),
          200,
        );
      }
      if (request.method == 'HEAD') {
        return http.Response(
          '',
          rejectFirstMedia && request.url.path.contains('/model-1/')
              ? 403
              : 200,
          headers: {'content-type': 'video/mp4'},
        );
      }
      expect(request.url.path, '/novel/player/multi_video_model/v1/');
      models++;
      final body = jsonDecode(request.body) as Map;
      final id = ((body['mixed_video_id_map'] as Map)['1004'] as List).single;
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            id: {
              if (validity != null) 'expire_time': (now + validity) ~/ 1000,
              'video_model': jsonEncode({
                'video_list': {
                  for (final quality in [1080, 720])
                    '$quality': {
                      'codec_type': 'h264',
                      'definition': '${quality}p',
                      'vwidth': quality,
                      'vheight': quality * 16 ~/ 9,
                      'main_url': base64Encode(
                        utf8.encode(
                          'https://fixture.qznovelvod.com/model-$models/$id/$quality.mp4',
                        ),
                      ),
                    },
                },
              }),
            },
          },
        }),
        200,
      );
    });
    final runtime = CatPawJsRuntime(client, null, '合成模型复用', false);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init('''
${source.replaceFirst('const existingPlay = spider.play;', "const existingPlay = async function(){return {url:''};};")}
const cacheTestPlay = spider.play;
spider.play = async function(flag, id, flags) {
  const options = flags[0];
  Date.now = () => options.now;
  if (options.reset) HongguoApp.resetGuestSession();
  return cacheTestPlay(flag, id, flags);
};
''');
    return (
      play:
          (
            String id, {
            int quality = 0,
            int advance = 0,
            String avoidUrl = '',
            bool reset = false,
          }) async {
            now += advance;
            return runtime.play(
              '',
              '7345678901234567000_$id',
              flags: [
                {
                  'now': now,
                  'quality': quality,
                  'avoidUrl': avoidUrl,
                  'reset': reset,
                },
              ],
            );
          },
      models: () => models,
      registrations: () => registrations,
    );
  }

  test('quality switching reuses the same valid model', () async {
    final f = await fixture();
    expect((await f.play(firstId)).quality, 1080);
    expect((await f.play(firstId, quality: 720)).quality, 720);
    expect((await f.play(firstId, quality: 1080)).quality, 1080);
    expect(f.models(), 1);
    expect(f.registrations(), 1);
  });

  test('models stay separate for different episodes', () async {
    final f = await fixture();
    await f.play(firstId);
    expect((await f.play(secondId)).url, contains(secondId));
    expect((await f.play(firstId)).url, contains(firstId));
    expect(f.models(), 2);
  });

  test('official expiry is not extended by reuse', () async {
    final f = await fixture(validity: 10000);
    final first = await f.play(firstId);
    final reused = await f.play(firstId, advance: 1000, quality: 720);
    expect(reused.expiresAt, first.expiresAt);
    expect(f.models(), 1);
    await f.play(firstId, advance: 5000);
    expect(f.models(), 2);
  });

  test('unknown expiry keeps the original thirty second boundary', () async {
    final f = await fixture(validity: null);
    final first = await f.play(firstId);
    final reused = await f.play(firstId, advance: 10000);
    expect(reused.expiresAt, first.expiresAt);
    expect(f.models(), 1);
    await f.play(firstId, advance: 16000);
    expect(f.models(), 2);
  });

  test('even long lived models are refreshed after five minutes', () async {
    final f = await fixture();
    await f.play(firstId);
    await f.play(firstId, advance: 240000);
    expect(f.models(), 1);
    await f.play(firstId, advance: 120000);
    expect(f.models(), 2);
  });

  test('player failure bypasses a cached model', () async {
    final f = await fixture();
    final first = await f.play(firstId);
    final next = await f.play(firstId, avoidUrl: first.url);
    expect(next.url, contains('/model-2/'));
    expect(f.models(), 2);
    expect(f.registrations(), 1);
  });

  test('rejected cached media refreshes once without guest churn', () async {
    final f = await fixture(rejectFirstMedia: true);
    final plan = await f.play(firstId);
    expect(plan.url, contains('/model-2/'));
    expect(f.models(), 2);
    expect(f.registrations(), 1);
  });

  test('guest reset cannot reuse the previous model', () async {
    final f = await fixture();
    await f.play(firstId);
    await f.play(firstId, reset: true);
    expect(f.models(), 2);
    expect(f.registrations(), 2);
  });
}
