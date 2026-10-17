import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('设备端官方源：元数据、分类、网络桥接与精确分集', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/novel/player/video_detail/v1/');
      return http.Response(
        jsonEncode({
          'data': {
            'video_data': {
              'series_title': '合成设备剧集',
              'video_list': [
                {'vid': '7345678901234568000'},
              ],
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(kPresetJsSources.single.script);
    expect((await runtime.getMeta())['id'], 'hongguo');
    expect((await runtime.home()).classes, hasLength(3));
    final detail = await runtime.detail('7345678901234567000');
    expect(calls, 1);
    expect(detail.vod['vod_name'], '合成设备剧集');
    expect(detail.vod['vod_play_url'], contains('7345678901234568000'));
  });

  testWidgets('设备端官方源：Base64 播放模型与错误重试', (tester) async {
    var reject = false;
    final client = MockClient((request) async {
      if (request.url.path == '/novel/player/video_model/v1/' && !reject) {
        return http.Response(
          jsonEncode({
            'data': {
              'video_model': {
                'video_list': {
                  'video_1': {
                    'main_url': base64Encode(
                      utf8.encode('https://media.example.test/current.mp4'),
                    ),
                    'video_meta': {'codec_type': 'h264'},
                  },
                },
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('', 404);
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(kPresetJsSources.single.script);
    const target =
        'https://hongguoduanju.com/player/7345678901234567000/7345678901234568000';
    expect(
      (await runtime.play('', target)).url,
      'https://media.example.test/current.mp4',
    );
    reject = true;
    expect((await runtime.play('', target)).url, isEmpty);
    reject = false;
    expect(
      (await runtime.play('', target)).url,
      'https://media.example.test/current.mp4',
    );
  });
}
