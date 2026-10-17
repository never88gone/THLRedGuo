import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';

void main() {
  final script = File('assets/sources/hongguo.js').readAsStringSync();
  const seriesId = '7345678901234567000';
  const videoId = '7345678901234568000';
  const playerUrl = 'https://hongguoduanju.com/player/$seriesId/$videoId';

  Future<CatPawJsRuntime> createRuntime(http.Client client) async {
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    return runtime;
  }

  test('Flutter、tvOS 与独立官方脚本保持完全一致', () {
    expect(kPresetJsSources.single.script.trim(), script.trim());
    final swift = File(
      'tvos/THLRedLook/ViewModels/LibraryViewModel.swift',
    ).readAsStringSync();
    const opening = 'public let BuiltInHongguoJSContent = #"""\n';
    final start = swift.indexOf(opening) + opening.length;
    final end = swift.indexOf('\n"""#', start);
    expect(swift.substring(start, end).trim(), script.trim());
  });

  for (final prefix in ['', 'hongguo:']) {
    test('媒体直链保留协议、端口与查询参数 ($prefix)', () async {
      final runtime = await createRuntime(
        MockClient((request) async {
          fail('媒体直链不应触发网页、App 或图片请求: ${request.url}');
        }),
      );
      const url = 'https://media.example.test:8443/clip.mp4?token=a:b&x=1';
      expect((await runtime.play('', '$prefix$url')).url, url);
    });
  }

  test('长整型 ID 末尾为 000 时仍保留全部分集，未知权限不标记为受限', () async {
    final runtime = await createRuntime(
      MockClient((request) async {
        expect(request.url.path, '/novel/player/video_detail/v1/');
        expect(jsonDecode(request.body)['series_id'], seriesId);
        return http.Response(
          jsonEncode({
            'data': {
              'video_data': {
                'series_title': '合成剧集',
                'video_list': List.generate(
                  4,
                  (index) => {
                    'vid': index == 0 ? videoId : '${videoId}_$index',
                  },
                ),
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final detail = await runtime.detail(seriesId);
    expect((detail.vod['vod_play_url'] as String).split('#'), hasLength(4));
    expect(detail.vod['vod_play_url'], contains(videoId));
    expect(detail.vod['accessible_count'], 0);
  });

  for (final response in [
    (404, 'video/mp4'),
    (200, 'text/html'),
    (403, 'video/mp4'),
  ]) {
    test('公共媒体探测 ${response.$1}/${response.$2} 时不返回伪链接', () async {
      final runtime = await createRuntime(
        MockClient((request) async {
          if (request.url.path.contains('/video/public/')) {
            expect(request.method, 'HEAD');
            return http.Response(
              '',
              response.$1,
              headers: {'content-type': response.$2},
            );
          }
          return http.Response('', 404);
        }),
      );
      expect((await runtime.play('', playerUrl)).url, isEmpty);
    });
  }

  test('公共媒体经 HEAD 确认为视频后只报告实际的 360P', () async {
    final requested = <http.Request>[];
    final runtime = await createRuntime(
      MockClient((request) async {
        requested.add(request);
        if (request.method == 'HEAD') {
          return http.Response('', 206, headers: {'content-type': 'video/mp4'});
        }
        return http.Response('', 404);
      }),
    );
    final play = await runtime.play('', playerUrl);
    expect(
      play.url,
      'https://hongguoduanju.com/video/public/$videoId/360p.mp4',
    );
    expect(play.quality, 360);
    expect(play.qualities, [360]);
    expect(play.header['Referer'], playerUrl);
    expect(
      requested.where((request) => request.method == 'HEAD'),
      hasLength(1),
    );
  });

  test('网络失败后允许重试当前分集，保留原始 HTTPS 播放页', () async {
    var attempts = 0;
    final runtime = await createRuntime(
      MockClient((request) async {
        if (request.url.path.startsWith('/player/')) {
          expect(request.url.toString(), playerUrl);
          attempts++;
          if (attempts == 1) return http.Response('', 503);
          return http.Response(
            '{"main_url":"https://media.example.test/current.mp4"}',
            200,
          );
        }
        return http.Response('', 404);
      }),
    );
    expect((await runtime.play('', playerUrl)).url, isEmpty);
    expect(
      (await runtime.play('', playerUrl)).url,
      'https://media.example.test/current.mp4',
    );
  });

  test('搜索保留末尾为 000 的合法 ID，且不下载封面', () async {
    final runtime = await createRuntime(
      MockClient((request) async {
        expect(request.url.path, '/incent_resource/suggestion');
        return http.Response(
          jsonEncode({
            'suggest_list': [
              {
                'series_id': seriesId,
                'name': '合成搜索结果',
                'video_data': {
                  'cover_url': 'https://images.example.test/poster.jpg',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect((await runtime.search('合成')).list.single['vod_id'], seriesId);
  });

  test('没有 Buffer 和 atob 的端侧沙箱也能解析 Base64 播放模型', () async {
    final runtime = await createRuntime(
      MockClient((request) async {
        expect(request.url.path, '/novel/player/video_model/v1/');
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
      }),
    );
    expect(
      (await runtime.play('', playerUrl)).url,
      'https://media.example.test/current.mp4',
    );
  });
}
