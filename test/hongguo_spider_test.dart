import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/pages/settings/source_diagnostics_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  final script = File('assets/sources/hongguo.js').readAsStringSync();
  http.Response registration() => http.Response(
    '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
    200,
  );
  http.Response page(List<Map<String, Object?>> rows) => http.Response(
    jsonEncode({
      'code': 0,
      'search_tabs': [
        {'tab_type': 29, 'data': rows, 'has_more': false, 'next_offset': 0},
      ],
    }),
    200,
  );
  test('诊断保留注册 DNS 失败，报告不含设备标识或请求参数', () async {
    final diagnostics = SourceDiagnostics();
    var searches = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/service/2/device_register/') {
        throw http.ClientException(
          'Failed host lookup: private-device-cookie-secret',
          request.url,
        );
      }
      searches++;
      return page([]);
    });
    final runtime = CatPawJsRuntime(client, diagnostics);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    await expectLater(
      runtime.search('private-keyword-secret'),
      throwsA(isA<Exception>()),
    );
    final registration = diagnostics.entries.first;
    expect(registration.stage, '游客注册');
    expect(registration.errorCode, 'DNS');
    expect(searches, 0);
    final report = diagnostics.report(
      version: '1.0.0+123',
      sourceHash: 'synthetic',
    );
    expect(report, contains('DNS'));
    expect(report, isNot(contains('private-')));
    expect(report, isNot(contains('aid=')));
  });

  test('诊断识别 HTTP 200 内的业务拒绝与会话重建', () async {
    final diagnostics = SourceDiagnostics();
    var searches = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/service/2/device_register/') {
        return registration();
      }
      searches++;
      return searches == 1
          ? http.Response(
              '{"code":1001,"message":"private-cookie-secret"}',
              200,
            )
          : page([]);
    });
    final runtime = CatPawJsRuntime(client, diagnostics);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    expect((await runtime.search('合成')).list, isEmpty);
    final denied = diagnostics.entries.firstWhere((e) => e.failed);
    expect(denied.status, 200);
    expect(denied.businessCode, '1001');
    expect(denied.errorCode, 'BUSINESS_REJECTED');
    expect(diagnostics.entries.where((e) => e.stage == '游客注册').length, 2);
    final report = diagnostics.report(
      version: '1.0.0+123',
      sourceHash: 'synthetic',
    );
    expect(report, isNot(contains('7345678901234567100')));
    expect(report, isNot(contains('private-cookie-secret')));
    expect(report, isNot(contains('x-medusa')));
    expect(SourceDiagnostics.safeCode('7345678901234567100'), isEmpty);
    for (var i = 0; i < 70; i++) {
      diagnostics.record(
        url:
            'https://reading.snssdk.com/reading/bookapi/search/tab/v?secret=private',
        context: '测试',
        elapsedMs: 3,
        status: 403,
      );
    }
    expect(diagnostics.entries.length, 60);
    diagnostics.clear();
    expect(diagnostics.entries, isEmpty);
  });

  testWidgets('诊断页显示失败阶段、复制脱敏报告并清空记录', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'THL',
      packageName: 'com.example.test',
      version: '1.0.0',
      buildNumber: '123',
      buildSignature: '',
    );
    final recorder = SourceDiagnostics.shared;
    recorder.clear();
    recorder.record(
      url:
          'https://log.snssdk.com/service/2/device_register/?device_id=private-secret',
      context: '日常使用',
      elapsedMs: 12,
      errorCode: 'DNS',
    );
    String clipboard = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      recorder.clear();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(const MaterialApp(home: SourceDiagnosticsPage()));
    await tester.pumpAndSettle();
    expect(find.text('数据源诊断'), findsOneWidget);
    expect(find.textContaining('DNS'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('source-diagnostics-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, contains('1.0.0+123'));
    expect(clipboard, contains('DNS'));
    expect(clipboard, isNot(contains('private-secret')));
    await tester.tap(find.text('清空诊断记录'));
    await tester.pumpAndSettle();
    expect(find.text('暂无记录，请先复现问题或开始检测。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('官方数据源 (hongguo.js) 自动化规范与链路测试', () {
    late String hongguoScript;

    setUpAll(() async {
      final file = File('assets/sources/hongguo.js');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'assets/sources/hongguo.js 文件必须存在',
      );
      hongguoScript = await file.readAsString();
      expect(hongguoScript, isNotEmpty);
    });

    test('1. 元数据 (meta) 与 CatPawOpen 规范契约验证', () async {
      expect(hongguoScript.contains('id: "hongguo"'), isTrue);
      expect(hongguoScript.contains('name: "官方免费短剧"'), isTrue);
      expect(hongguoScript.contains('version: "1.1.0-dev.6"'), isTrue);
      expect(
        hongguoScript.contains('"search"') &&
            hongguoScript.contains('"categories"') &&
            hongguoScript.contains('"danmaku"'),
        isTrue,
      );
      expect(hongguoScript.contains('type: "video"'), isTrue);
      expect(
        hongguoScript.contains('BASE_URL = "https://hongguoduanju.com"'),
        isTrue,
      );
      expect(hongguoScript.contains('var spider = {'), isTrue);
    });

    test('2. 沙箱加载与 getMeta() 读取元数据测试', () async {
      final runtime = CatPawJsRuntime();
      await runtime.init(hongguoScript);
      expect(runtime.isReady, isTrue);

      final meta = await runtime.getMeta();
      expect(meta['id'], equals('hongguo'));
      expect(meta['name'], equals('官方免费短剧'));
      expect(meta['version'], equals('1.1.0-dev.6'));
      expect(meta['type'], equals('video'));
      expect(
        meta['features'],
        containsAll(['search', 'categories', 'danmaku']),
      );

      runtime.dispose();
    });

    test('3. home() 分类列表提取测试', () async {
      final runtime = CatPawJsRuntime();
      await runtime.init(hongguoScript);

      final homeRes = await runtime.home();
      expect(homeRes.classes, isNotEmpty);
      final typeIds = homeRes.classes.map((c) => c['type_id']).toList();
      final typeNames = homeRes.classes.map((c) => c['type_name']).toList();

      expect(typeIds, containsAll(['real-drama', 'comic-drama', 'ai-drama']));
      expect(typeNames, containsAll(['真人剧', '漫剧', 'AI剧']));

      runtime.dispose();
    });

    test('4. category() 分类目录解析测试 (RouterData 与推荐列表)', () async {
      final fakeRouterData = {
        'loaderData': {
          'root': {
            'recommendList': [
              {
                'series_id_str': '7345678901234567890',
                'series_title': '战神归来当赘婿',
                'series_cover': 'https://p3.example.com/cover1.jpg',
                'episode_cnt': 80,
                'episode_right_text': '全80集',
                'series_intro': '五年前他是一代战神，五年后回归都市隐姓埋名...',
                'tags': ['都市', '战神', '爽文'],
              },
              {
                'series_id_str': '7345678901234567891',
                'series_title': '龙王令之至尊归来',
                'series_cover': 'https://p3.example.com/cover2.jpg',
                'episode_cnt': 100,
                'episode_right_text': '全100集',
                'series_intro': '十万龙王将士恭迎龙王回朝！',
                'tags': ['热血', '至尊'],
              },
            ],
          },
        },
      };

      final fakeHtml =
          '''
<!DOCTYPE html>
<html>
<head><title>短剧 - 分类</title></head>
<body>
<script>
window._ROUTER_DATA = ${jsonEncode(fakeRouterData)};
</script>
</body>
</html>
''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/category/')) {
          return http.Response(
            fakeHtml,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final runtime = CatPawJsRuntime(mockClient);
      await runtime.init(hongguoScript);

      final catRes = await runtime.category('real-drama', 1);
      expect(catRes.list.length, equals(2));

      final first = catRes.list.first;
      expect(first['vod_id'], equals('7345678901234567890'));
      expect(first['vod_name'], equals('战神归来当赘婿'));
      expect(first['vod_pic'], equals('https://p3.example.com/cover1.jpg'));
      expect(first['vod_remarks'], equals('全80集'));
      expect(first['vod_content'], contains('一代战神'));
      expect(first['vod_tag'], contains('都市'));

      final second = catRes.list[1];
      expect(second['vod_id'], equals('7345678901234567891'));
      expect(second['vod_name'], equals('龙王令之至尊归来'));
      expect(second['vod_remarks'], equals('全100集'));

      runtime.dispose();
    });

    test('5. detail() 剧集详情与选集生成测试', () async {
      final fakeDetailRouterData = {
        'loaderData': {
          'detail': {
            'seriesDetail': {
              'series_id': '7345678901234567890',
              'series_name': '战神归来当赘婿',
              'series_cover': 'https://p3.example.com/cover1_large.jpg',
              'series_intro': '五年前一代战神横扫八荒，今朝龙隐于渊守护至爱...',
              'vid_list': ['vid_001', 'vid_002', 'vid_003', 'vid_004'],
            },
          },
        },
      };

      final fakeDetailHtml =
          '''
<!DOCTYPE html>
<html>
<head><title>详情页</title></head>
<body>
<script>
window._ROUTER_DATA = ${jsonEncode(fakeDetailRouterData)};
</script>
</body>
</html>
''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/detail')) {
          return http.Response(
            fakeDetailHtml,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final runtime = CatPawJsRuntime(mockClient);
      await runtime.init(hongguoScript);

      final detailRes = await runtime.detail('7345678901234567890');
      final vod = detailRes.vod;
      expect(vod, isNotEmpty);
      expect(vod['vod_name'], equals('战神归来当赘婿'));
      expect(vod['vod_pic'], equals('https://p3.example.com/cover1_large.jpg'));
      expect(vod['vod_remarks'], equals('全4集'));
      expect(vod['vod_play_from'], equals('官方直链'));

      final playUrl = vod['vod_play_url'] as String;
      expect(playUrl, isNotEmpty);
      final episodes = playUrl.split('#');
      expect(episodes.length, equals(4));
      expect(
        episodes[0],
        startsWith(
          '第1集\$https://hongguoduanju.com/player/7345678901234567890/vid_001',
        ),
      );
      expect(
        episodes[1],
        startsWith(
          '第2集\$https://hongguoduanju.com/player/7345678901234567890/vid_002',
        ),
      );
      expect(
        episodes[3],
        startsWith(
          '第4集\$https://hongguoduanju.com/player/7345678901234567890/vid_004',
        ),
      );

      runtime.dispose();
    });

    test('6. play() 取流解析测试 (提取真实播放直链与防盗链 Headers)', () async {
      final fakePlayerHtml = '''
<!DOCTYPE html>
<html>
<head><title>播放器</title></head>
<body>
<script>
window.__INITIAL_DATA__ = {
  "video": {
    "main_url": "https://v9-dy-y.hongguoduanju.com/video/tos/cn/stream_hd.mp4?auth_key=123456"
  }
};
</script>
</body>
</html>
''';

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/player/')) {
          return http.Response(
            fakePlayerHtml,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final runtime = CatPawJsRuntime(mockClient);
      await runtime.init(hongguoScript);

      final playRes = await runtime.play(
        'flag',
        'https://hongguoduanju.com/player/7345678901234567890/vid_001',
      );

      expect(
        playRes.url,
        equals(
          'https://v9-dy-y.hongguoduanju.com/video/tos/cn/stream_hd.mp4?auth_key=123456',
        ),
      );
      expect(
        playRes.header['Referer'],
        equals('https://hongguoduanju.com/player/7345678901234567890/vid_001'),
      );
      expect(playRes.header['User-Agent'], isNotEmpty);

      runtime.dispose();
    });

    test('7. App 搜索注册会话、精确 ID 与分页传递', () async {
      var registrations = 0;
      final mockClient = MockClient((request) async {
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
        expect(request.url.path, '/reading/bookapi/search/tab/v');
        expect(request.url.queryParameters['tab_type'], '29');
        return http.Response(
          jsonEncode({
            'code': 0,
            'search_tabs': [
              {
                'tab_type': 29,
                'has_more': false,
                'next_offset': 2,
                'data': [
                  {
                    'video_data': [
                      {
                        'series_id': '7345678909999999991',
                        'title': '重生后被霸总宠上天',
                        'cover':
                            'https://images.example.test/never-request.jpg',
                        'episode_cnt': 95,
                        'video_detail': {'series_intro': '重生归来逆袭人生'},
                      },
                    ],
                  },
                  {
                    'video_data': [
                      {
                        'series_id': '7345678909999999992',
                        'title': '真假千金重逢时',
                        'episode_cnt': 70,
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
      });
      final runtime = CatPawJsRuntime(mockClient);
      await runtime.init(hongguoScript);
      final result = await runtime.search('重生');
      expect(registrations, 1);
      expect(result.list.map((row) => row['vod_id']), [
        '7345678909999999991',
        '7345678909999999992',
      ]);
      expect(result.list.first['vod_remarks'], '全95集');
      expect(result.list.first['vod_content'], contains('逆袭人生'));
      expect(result.hasMore, isFalse);
      runtime.dispose();
    });

    test(
      '8. 仓库纯净红线验证：assets/sources 仅允许包含 hongguo.js (其余源归属于本地 GitLab thlredguojs)',
      () {
        final sourcesDir = Directory('assets/sources');
        expect(sourcesDir.existsSync(), isTrue);

        final files = sourcesDir
            .listSync()
            .whereType<File>()
            .where((f) => !f.path.endsWith('.DS_Store'))
            .toList();

        final fileNames = files.map((f) => f.uri.pathSegments.last).toList();
        // 验证仅存在且只允许 hongguo.js
        expect(
          fileNames,
          equals(['hongguo.js']),
          reason:
              'GitHub 仓库 assets/sources 目录严禁混入任何第三方数据源，其余源应保存在本地 GitLab thlredguojs 项目',
        );
      },
    );
  });
}
