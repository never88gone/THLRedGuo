import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/js_source_presets.dart';

void main() {
  setUp(() {
    CatPawJsRuntime.resetDeviceSessionForTesting();
  });

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

  test('Flutter、tvOS 与独立官方脚本保持完全一致', () async {
    final presetScript = await kPresetJsSources.single.loadScript();
    expect(presetScript.trim(), script.trim());
    expect(kPresetJsSources.single.loadScriptSync().trim(), script.trim());
    final swift = File(
      'tvos/THLRedLook/ViewModels/LibraryViewModel.swift',
    ).readAsStringSync();
    expect(
      swift,
      contains('Bundle.main.url(forResource: "hongguo", withExtension: "js")'),
    );
    expect(swift, isNot(contains('public let BuiltInHongguoJSContent = #')));
  });

  test('取消取流会中止当前网络请求，且不会阻止下一次播放', () async {
    final started = Completer<void>();
    var calls = 0;
    final client = MockClient.streaming((request, body) async {
      if (++calls == 1) {
        started.complete();
        await (request as http.AbortableRequest).abortTrigger;
        throw StateError('synthetic cancellation');
      }
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init('''
var spider = { play: async function() {
  const response = await fetch("https://api.example.test/synthetic");
  return { url: response.status === 200 ? "https://media.example.test/clear.mp4" : "" };
} };
''');
    final first = runtime.play('', 'synthetic');
    await started.future;
    final cancelled = expectLater(first, throwsA(isA<CatPawSourceFailure>()));
    runtime.cancelPending();
    await cancelled.timeout(const Duration(seconds: 1));
    expect(
      (await runtime.play('', 'synthetic')).url,
      'https://media.example.test/clear.mp4',
    );
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
        if (request.url.path.contains('device_register')) {
          return http.Response(
            jsonEncode({
              'device_id_str': '7345678901234567100',
              'install_id_str': '7345678901234567200',
            }),
            200,
          );
        }
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
    expect(
      play.header.keys.map((key) => key.toLowerCase()),
      isNot(contains('referer')),
    );
    expect(
      requested.where((request) => request.method == 'HEAD'),
      hasLength(2),
    );
  });

  test('网络失败后允许重试当前分集，保留原始 HTTPS 播放页', () async {
    var attempts = 0;
    final runtime = await createRuntime(
      MockClient((request) async {
        if (request.method == 'HEAD' &&
            request.url.path.contains('/video/public/') &&
            attempts > 1) {
          return http.Response('', 200, headers: {'content-type': 'video/mp4'});
        }
        if (request.url.path.startsWith('/player/')) {
          expect(request.url.toString(), playerUrl);
          attempts++;
          if (attempts == 1) return http.Response('', 503);
          return http.Response(
            '{"main_url":"https://hongguoduanju.com/video/public/$videoId/360p.mp4"}',
            200,
          );
        }
        return http.Response('', 404);
      }),
    );
    expect((await runtime.play('', playerUrl)).url, isEmpty);
    expect(
      (await runtime.play('', playerUrl)).url,
      'https://hongguoduanju.com/video/public/$videoId/360p.mp4',
    );
  });

  test('搜索保留末尾为 000 的合法 ID，且不下载封面', () async {
    final runtime = await createRuntime(
      MockClient((request) async {
        if (request.url.path == '/service/2/device_register/') {
          return http.Response(
            jsonEncode({
              'device_id_str': '7345678901234567001',
              'install_id_str': '7345678901234567002',
            }),
            200,
          );
        }
        expect(request.url.path, '/reading/bookapi/search/tab/v');
        return http.Response(
          jsonEncode({
            'code': 0,
            'search_tabs': [
              {
                'tab_type': 29,
                'has_more': false,
                'data': [
                  {
                    'video_data': [
                      {
                        'series_id': int.parse(seriesId),
                        'title': '合成搜索结果',
                        'cover': 'https://images.example.test/poster.jpg',
                      },
                    ],
                  },
                ],
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

  test('旧模型含加密信息时改用完整 App 模型并保留内容密钥', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/novel/player/video_model/v1/') {
        return http.Response(
          jsonEncode({
            'data': {
              'video_model': {
                'video_list': {
                  'video_1': {
                    'main_url': base64Encode(
                      utf8.encode('https://fixture.qznovelvod.com/legacy.mp4'),
                    ),
                    'codec_type': 'h264',
                    'spade_a': 'synthetic-encryption-marker',
                  },
                },
              },
            },
          }),
          200,
        );
      }
      if (request.url.path == '/selected.mp4' && request.method == 'HEAD') {
        return http.Response('', 200, headers: {'content-type': 'video/mp4'});
      }
      expect(request.url.path, isNot('/legacy.mp4'));
      return http.Response('', 404);
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init('''$script
HongguoApp.fetchAppPlayUrl = async function(vid) {
  if (vid !== "$videoId") throw new Error("wrong episode");
  return { variants: [{ vid: vid, url: "https://fixture.qznovelvod.com/selected.mp4", contentKey: "${'1' * 32}", quality: "1080p", userAgent: "synthetic", referer: "https://novelquickapp.com/" }] };
};
''');
    final result = await runtime.play('', playerUrl);
    expect(result.url, 'https://fixture.qznovelvod.com/selected.mp4');
    expect(result.decryptionKey, '1' * 32);
    expect(result.quality, 1080);
    expect(
      result.expiresAt,
      greaterThan(DateTime.now().millisecondsSinceEpoch),
    );
  });

  for (final rejectDirect in [false, true]) {
    test('注册访客使用 App 直返模型，直返拒绝才请求 fallback ($rejectDirect)', () async {
      var registrations = 0;
      var fallbackCalls = 0;
      final runtime = await createRuntime(
        MockClient((request) async {
          expect(
            request.url.host,
            isNot('hongguoduanju.com'),
            reason: 'App 可播时不请求公开网页或媒体',
          );
          if (request.url.path == '/service/2/device_register/') {
            registrations++;
            return http.Response(
              jsonEncode({
                'device_id_str': '7345678901234567001',
                'install_id_str': '7345678901234567002',
              }),
              200,
            );
          }
          Map<String, Object?> model(String name) => {
            'video_list': {
              'video_1': {
                'main_url': base64Encode(
                  utf8.encode('https://fixture.qznovelvod.com/$name.mp4'),
                ),
                'codec_type': 'h264',
                'definition': '1080p',
              },
            },
          };
          if (request.url.path == '/novel/player/multi_video_model/v1/') {
            expect(
              request.url.queryParameters['device_id'],
              '7345678901234567001',
            );
            expect(request.url.queryParameters['version_code'], '73932');
            expect(jsonDecode(request.body)['mixed_video_id_map']['1004'], [
              videoId,
            ]);
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  videoId: {
                    'video_model': {
                      ...model('direct'),
                      'fallback_api': 'https://fixture.fqnovel.com/fallback',
                    },
                  },
                },
              }),
              200,
            );
          }
          if (request.url.path == '/fallback') {
            fallbackCalls++;
            expect(rejectDirect, isTrue);
            return http.Response(
              jsonEncode({
                'video_info': {'data': model('fallback')},
              }),
              200,
            );
          }
          if (request.url.host == 'fixture.qznovelvod.com') {
            expect(request.method, 'HEAD');
            return http.Response(
              '',
              rejectDirect && request.url.path == '/direct.mp4' ? 403 : 200,
              headers: {'content-type': 'video/mp4'},
            );
          }
          return http.Response('', 404);
        }),
      );
      final result = await runtime.play('', playerUrl);
      expect(
        result.url,
        'https://fixture.qznovelvod.com/${rejectDirect ? 'fallback' : 'direct'}.mp4',
      );
      expect(registrations, 1);
      expect(fallbackCalls, rejectDirect ? 1 : 0);
    });
  }

  for (final codec in ['h264', '', 'av1']) {
    test('DASH 模型改取官方合并 MP4 并保留精确分集 ($codec)', () async {
      var fallbackCalls = 0;
      final runtime = await createRuntime(
        MockClient((request) async {
          if (request.url.path == '/service/2/device_register/') {
            return http.Response(
              jsonEncode({
                'device_id_str': '7345678901234567001',
                'install_id_str': '7345678901234567002',
              }),
              200,
            );
          }
          if (request.url.path == '/novel/player/multi_video_model/v1/') {
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  videoId: {
                    'video_model': {
                      'dynamic_video': {'dynamic_type': 'segment_base'},
                      'fallback_api': {
                        'fallback_api':
                            'https://fixture.snssdk.com/fallback?format_type=dash&ptoken=synthetic%2Btoken&vps=4&force_fids=synthetic-file',
                      },
                    },
                  },
                },
              }),
              200,
            );
          }
          if (request.url.path == '/fallback') {
            fallbackCalls++;
            expect(request.url.queryParameters['format_type'], 'mp4');
            expect(request.url.queryParameters['ptoken'], 'synthetic+token');
            expect(request.url.queryParameters['vps'], '4');
            expect(
              request.url.queryParameters.containsKey('force_fids'),
              isFalse,
            );
            return http.Response(
              jsonEncode({
                'video_info': {
                  'data': {
                    'video_list': {
                      'video_1': {
                        'main_url': base64Encode(
                          utf8.encode(
                            'https://fixture.qznovelvod.com/refused.mp4',
                          ),
                        ),
                        'backup_url_1': base64Encode(
                          utf8.encode(
                            'https://fixture.qznovelvod.com/merged.mp4',
                          ),
                        ),
                        'codec_type': codec,
                        'vtype': 'mpeg',
                        'definition': '1080p',
                      },
                    },
                  },
                },
              }),
              200,
            );
          }
          if (request.url.host == 'fixture.qznovelvod.com') {
            expect(request.method, 'HEAD');
            return http.Response(
              '',
              request.url.path == '/merged.mp4' ? 200 : 403,
              headers: {'content-type': 'video/mp4'},
            );
          }
          return http.Response('', 404);
        }),
      );
      final result = await runtime.play('', playerUrl);
      expect(
        result.url,
        codec == 'av1' ? isEmpty : 'https://fixture.qznovelvod.com/merged.mp4',
      );
      expect(fallbackCalls, greaterThan(0));
    });
  }

  test('App 优先取流，恢复时避开同一地址并使用准确备选分集', () async {
    final client = MockClient((request) async {
      if (request.method == 'HEAD') {
        return http.Response('', 200, headers: {'content-type': 'video/mp4'});
      }
      return http.Response('', 404);
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init('''$script
HongguoApp.fetchAppPlayUrl = async function(vid) {
  return {variants:["primary", "recovered"].map(name=>({vid:vid,url:"https://fixture.qznovelvod.com/"+name+".mp4",quality:"1080p",userAgent:"synthetic",referer:"https://novelquickapp.com/"}))};
};
''');
    final first = await runtime.play('', playerUrl);
    expect(first.url, 'https://fixture.qznovelvod.com/primary.mp4');
    final recovered = await runtime.play(
      '',
      playerUrl,
      flags: [
        {'avoidUrl': first.url},
      ],
    );
    expect(recovered.url, 'https://fixture.qznovelvod.com/recovered.mp4');
  });

  test('网页中其他分集的媒体不能替代当前所选分集', () async {
    final client = MockClient((request) async {
      if (request.url.path.startsWith('/player/')) {
        return http.Response(
          '{"contentUrl":"https://hongguoduanju.com/video/public/7345678901234568001/360p.mp4"}',
          200,
        );
      }
      expect(request.method, isNot('HEAD'));
      return http.Response('', 404);
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init('''$script
HongguoApp.fetchAppPlayUrl = async function() { const error = new Error("synthetic no model"); error.code = "MISSING_MODEL"; throw error; };
''');
    expect((await runtime.play('', playerUrl)).url, isEmpty);
  });

  test('没有 Buffer 和 atob 的端侧沙箱也能解析 Base64 播放模型', () async {
    final runtime = await createRuntime(
      MockClient((request) async {
        if (request.method == 'HEAD' &&
            request.url.host == 'media.example.test') {
          return http.Response('', 200, headers: {'content-type': 'video/mp4'});
        }
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

  test('同画质可用备用 CDN 不等待慢主线路', () async {
    final runtime = await createRuntime(
      MockClient((request) async {
        if (request.url.path == '/service/2/device_register/') {
          return http.Response(
            jsonEncode({
              'device_id_str': '7345678901234567001',
              'install_id_str': '7345678901234567002',
            }),
            200,
          );
        }
        if (request.url.path == '/novel/player/multi_video_model/v1/') {
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {
                videoId: {
                  'video_model': {
                    'video_list': {
                      'video_1': {
                        'main_url': base64Encode(
                          utf8.encode(
                            'https://fixture.qznovelvod.com/slow.mp4',
                          ),
                        ),
                        'backup_url_1': base64Encode(
                          utf8.encode(
                            'https://fixture.qznovelvod.com/fast.mp4',
                          ),
                        ),
                        'codec_type': 'h264',
                        'definition': '1080p',
                      },
                    },
                  },
                },
              },
            }),
            200,
          );
        }
        expect(request.method, 'HEAD');
        if (request.url.path == '/slow.mp4') {
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
        return http.Response('', 200, headers: {'content-type': 'video/mp4'});
      }),
    );
    final clock = Stopwatch()..start();
    expect(
      (await runtime.play('', playerUrl)).url,
      'https://fixture.qznovelvod.com/fast.mp4',
    );
    expect(clock.elapsedMilliseconds, lessThan(500));
  });

  test('设备 Session 持久化：首次注册后写入缓存，后续调用完全跳过注册网络请求', () async {
    var registerCalls = 0;
    http.Response handleRequest(http.Request request) {
      if (request.url.path == '/service/2/device_register/') {
        registerCalls++;
        return http.Response(
          jsonEncode({
            'device_id_str': '7345678901234567001',
            'install_id_str': '7345678901234567002',
          }),
          200,
        );
      }
      if (request.url.path == '/novel/player/multi_video_model/v1/') {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              videoId: {
                'video_model': {
                  'video_list': {
                    'video_1': {
                      'main_url': base64Encode(
                        utf8.encode(
                          'https://fixture.qznovelvod.com/cached.mp4',
                        ),
                      ),
                      'codec_type': 'h264',
                      'definition': '1080p',
                    },
                  },
                },
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.host == 'fixture.qznovelvod.com') {
        return http.Response('', 200, headers: {'content-type': 'video/mp4'});
      }
      return http.Response('', 404);
    }

    final client1 = MockClient((r) async => handleRequest(r));
    final runtime1 = await createRuntime(client1);
    final res1 = await runtime1.play('', playerUrl);
    expect(res1.url, 'https://fixture.qznovelvod.com/cached.mp4');
    expect(registerCalls, 1, reason: '首次运行由于无缓存，必须走一次设备注册');
    expect(CatPawJsRuntime.cachedDeviceSession, isNotNull);

    // 第二次新建运行时（模拟下次加载数据或打开 App）
    final client2 = MockClient((r) async => handleRequest(r));
    final runtime2 = await createRuntime(client2);
    final res2 = await runtime2.play('', playerUrl);
    expect(res2.url, 'https://fixture.qznovelvod.com/cached.mp4');
    expect(registerCalls, 1, reason: '由于设备缓存已就绪，第二次调用完全跳过设备注册');
  });
}
