import 'test_helpers/official_source_fixture.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/core/diagnostics/network_egress_lookup.dart';
import 'package:THLRedLook/pages/settings/source_diagnostics_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  final script = syntheticOfficialSource();
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
    expect(registration.url, contains('%5B'));
    expect(registration.url, isNot(contains('private-')));
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
    final network = MockClient(
      (_) async => http.Response('{"ip":"127.0.0.1"}', 200),
    );
    final recorder = SourceDiagnostics(
      networkLookup: NetworkEgressLookup(client: network),
    );
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
      network.close();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(
      MaterialApp(home: SourceDiagnosticsPage(diagnostics: recorder)),
    );
    await tester.pumpAndSettle();
    expect(find.text('数据源诊断'), findsOneWidget);
    expect(find.textContaining('DNS'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('source-diagnostics-copy')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
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
      hongguoScript = syntheticOfficialSource();
      expect(hongguoScript, isNotEmpty);
    });

    test('1. 元数据通过运行时接口保持官方 CatPawOpen 契约', () async {
      final runtime = CatPawJsRuntime();
      addTearDown(runtime.dispose);
      await runtime.init(hongguoScript);
      final meta = await runtime.getMeta();
      expect(meta['id'], 'hongguo');
      expect(meta['name'], '官方免费短剧');
      expect(meta['type'], 'video');
      expect(
        meta['features'],
        containsAll(['search', 'categories', 'danmaku']),
      );
    });
    test('2. 沙箱加载与 getMeta() 读取元数据测试', () async {
      final runtime = CatPawJsRuntime();
      await runtime.init(hongguoScript);
      expect(runtime.isReady, isTrue);

      final meta = await runtime.getMeta();
      expect(meta['id'], equals('hongguo'));
      expect(meta['name'], equals('官方免费短剧'));
      expect(meta['version'], matches(RegExp(r'^\d+\.\d+\.\d+')));
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

      final catRes = await runtime.category('legacy-category', 1);
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

    test('5. App 详情使用真实分集标识，不回退网页猜测', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/service/2/device_register/') {
          return registration();
        }
        expect(request.url.path, '/novel/player/video_detail/v1/');
        return http.Response(
          jsonEncode({
            'data': {
              'video_data': {
                'series_title': '合成详情',
                'video_list': [
                  {'vid': '7345678901234568001'},
                  {'vid': '7345678901234568002'},
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
      await runtime.init(hongguoScript);
      final result = await runtime.detail('7345678901234567001');
      expect(result.vod['vod_name'], '合成详情');
      expect((result.vod['vod_play_url'] as String).split('#'), hasLength(2));
      expect(result.vod['vod_play_url'], contains('7345678901234568001'));
    });
    test('6. App 播放解析真实模型地址，不使用网页预览兜底', () async {
      const media = 'https://synthetic.qznovelvod.com/video/synthetic.mp4';
      final client = MockClient((request) async {
        if (request.url.path == '/service/2/device_register/') {
          return registration();
        }
        if (request.url.host.endsWith('qznovelvod.com')) {
          return http.Response(
            'x',
            206,
            headers: {
              'content-type': 'video/mp4',
              'content-range': 'bytes 0-0/1024',
              'content-length': '1',
            },
          );
        }
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': {
              '7345678901234568001': {
                'video_model': {
                  'video_list': {
                    'main': {
                      'main_url': base64Encode(utf8.encode(media)),
                      'codec_type': 'h264',
                      'definition': '1080p',
                      'vwidth': 1080,
                      'vheight': 1920,
                    },
                  },
                },
              },
            },
          }),
          200,
        );
      });
      final runtime = CatPawJsRuntime(client);
      addTearDown(runtime.dispose);
      addTearDown(client.close);
      await runtime.init(hongguoScript);
      final result = await runtime.play(
        '',
        '7345678901234567001_7345678901234568001',
      );
      expect(result.url, media);
      expect(result.quality, 1080);
    });
    test('7. App 搜索注册会话、精确 ID 与分页传递', () async {
      SharedPreferences.setMockInitialValues({});
      CatPawJsRuntime.resetDeviceSessionForTesting(null);
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
