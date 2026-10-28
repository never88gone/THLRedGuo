import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_runner.dart';
import 'package:THLRedLook/core/diagnostics/network_egress_lookup.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/pages/settings/source_diagnostics_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final script = File('assets/sources/hongguo.js').readAsStringSync();
  const registration =
      '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}';
  const emptyTabs =
      '{"code":0,"search_tabs":[{"tab_type":11,"title":"综合","data":[]},{"tab_type":1,"title":"小说","data":[]},{"tab_type":2,"title":"听书","data":[]}]}';
  const success =
      '{"code":0,"search_tabs":[{"tab_type":29,"title":"剧集","data":[{"video_data":[{"series_id":"7345678901234567000","title":"合成剧","episode_cnt":30}]}]}]}';
  http.Response json(String body) => http.Response(
    body,
    200,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'x-tt-logid': 'synthetic-log-001',
    },
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatPawJsRuntime.resetDeviceSessionForTesting();
  });

  test(
    'filtered category response preserves status, log ID and failure cause',
    () async {
      final recorder = SourceDiagnostics();
      final client = MockClient(
        (r) async => json(
          r.url.path.contains('device_register') ? registration : emptyTabs,
        ),
      );
      final runtime = CatPawJsRuntime(client, recorder, '合成诊断', false);
      addTearDown(runtime.dispose);
      addTearDown(client.close);
      await runtime.init(script);
      await expectLater(
        runtime.search('private-query'),
        throwsA(
          isA<CatPawSourceFailure>().having(
            (e) => e.code,
            'code',
            'SEARCH_TAB_MISSING',
          ),
        ),
      );
      final execution = recorder.entries.lastWhere((e) => e.stage == '搜索执行');
      expect(execution.errorCategory, 'DATA_PARSE');
      expect(execution.status, 200);
      expect(execution.businessCode, '0');
      expect(execution.logId, 'synthetic-log-001');
      expect(execution.searchTabsSummary, contains('11:综合'));
      expect(execution.sessionStatus, '独立游客会话');
      final report = recorder.report(version: '1.0.0', sourceHash: 'synthetic');
      expect(report, contains('SEARCH_TAB_MISSING'));
      expect(report, contains('无法确定地区限制'));
      expect(report, isNot(contains('private-query')));
    },
  );

  test(
    'DNS retry keeps native cause and reuses the registered session',
    () async {
      var requests = 0;
      var registrations = 0;
      final recorder = SourceDiagnostics();
      final client = MockClient((r) async {
        if (r.url.path.contains('device_register')) {
          registrations++;
          return json(registration);
        }
        if (++requests == 1) throw const SocketException('Failed host lookup');
        return json(success);
      });
      final runtime = CatPawJsRuntime(client, recorder, '合成断线', false);
      addTearDown(runtime.dispose);
      addTearDown(client.close);
      await runtime.init(script);
      expect((await runtime.search('合成剧')).list, hasLength(1));
      expect(requests, 2);
      expect(registrations, 1);
      expect(recorder.entries.any((e) => e.errorCode == 'DNS'), isTrue);
    },
  );

  test(
    'independent diagnostics never injects or overwrites the normal guest',
    () async {
      const previous =
          '{"device_id":"7345678901234567300","iid":"7345678901234567400"}';
      SharedPreferences.setMockInitialValues({
        'thl_hongguo_device_session': previous,
      });
      CatPawJsRuntime.resetDeviceSessionForTesting(previous);
      var registrations = 0;
      final client = MockClient((r) async {
        if (r.url.path.contains('device_register')) {
          registrations++;
          return json(registration);
        }
        expect(
          r.url.queryParameters['device_id'],
          isNot('7345678901234567300'),
        );
        return json(success);
      });
      final runtime = CatPawJsRuntime(
        client,
        SourceDiagnostics(),
        '独立会话',
        false,
      );
      addTearDown(runtime.dispose);
      addTearDown(client.close);
      await runtime.init(script);
      await runtime.search('合成剧');
      expect(registrations, 1);
      expect(CatPawJsRuntime.cachedDeviceSession, previous);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'thl_hongguo_device_session',
        ),
        previous,
      );
    },
  );

  test(
    'empty diagnostic search cannot pass skipped detail and stream checks',
    () async {
      final recorder = SourceDiagnostics();
      final runner = SourceDiagnosticRunner(
        diagnostics: recorder,
        runtimeFactory: (log, context) =>
            CatPawJsRuntime(null, log, context, false),
        scriptLoader: () async =>
            'var spider={search:async function(){return {list:[],page:1,pagecount:1};}};',
      );
      addTearDown(runner.dispose);
      await runner.run();
      expect(runner.failureCount, 1);
      expect(runner.result, contains('检测失败'));
      expect(recorder.entries.last.errorCode, 'SEARCH_EMPTY');
      expect(recorder.entries.any((e) => e.stage.contains('播放流')), isFalse);
    },
  );

  test('report removes secrets and raw bodies but retains cursor diagnostics', () {
    final recorder = SourceDiagnostics();
    recorder.record(
      url:
          'https://private-user:private-password@reading.snssdk.com/reading/bookapi/search/tab/v?query=private-query&tab_type=11&offset=6&device_id=private-device#private-fragment',
      context: '合成记录',
      elapsedMs: 42,
      status: 200,
      body: jsonEncode({
        'code': 0,
        'device_id_str': 'private-device',
        'query': 'private-query',
        'cookie': 'private-cookie',
        'search_tabs': [
          {'tab_type': 11, 'title': '综合', 'data': []},
        ],
      }),
      headers: {'X-Tt-Logid': 'synthetic-log-001'},
    );
    final report = recorder.report(version: '1.0.0', sourceHash: 'synthetic');
    expect(report, isNot(contains('private-')));
    expect(report, contains('tab_type=11'));
    expect(report, contains('offset=6'));
    expect(report, contains('synthetic-log-001'));
    expect(report, contains('响应结构摘要'));
    expect(
      SourceDiagnostics.redact(
        'Authorization: Bearer private-token\nCookie: sid=private-session; other=private-cookie\n{"device_id_str":"private-device"}',
      ),
      isNot(contains('private-')),
    );
    expect(
      SourceDiagnostics().report(version: '1.0.0', sourceHash: 'synthetic'),
      contains('尚未检测'),
    );
  });

  test('search HTML and timeout cancellation retain the correct category', () {
    final parsed = SourceDiagnostics.analyzeHttpResponse(
      200,
      '<html>gateway</html>',
      stage: '搜索',
    );
    expect(parsed.code, 'INVALID_RESPONSE');
    final recorder = SourceDiagnostics();
    recorder.record(
      url: 'https://reading.snssdk.com/reading/bookapi/search/tab/v',
      context: '合成超时',
      elapsedMs: 12,
      error: http.RequestAbortedException(),
      timedOut: true,
    );
    expect(recorder.entries.single.errorCode, 'TIMEOUT');
  });

  testWidgets('phone portrait exposes export action and category evidence', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    PackageInfo.setMockInitialValues(
      appName: 'THL',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '262901343',
      buildSignature: '',
    );
    SourceDiagnostics.shared.clear();
    addTearDown(SourceDiagnostics.shared.clear);
    final egressClient = MockClient(
      (request) async => http.Response(
        '{"ip":"203.0.113.23","country":"Synthetic Region","country_code":"TW"}',
        200,
      ),
    );
    addTearDown(egressClient.close);
    final recorder = SourceDiagnostics(
      networkLookup: NetworkEgressLookup(client: egressClient),
    );
    addTearDown(recorder.dispose);
    await t.runAsync(() => recorder.refreshNetworkEgress());
    recorder.record(
      url: 'https://reading.snssdk.com/reading/bookapi/search/tab/v',
      context: '合成界面',
      elapsedMs: 3,
      status: 200,
      body: emptyTabs,
      headers: {'x-tt-logid': 'synthetic-log-001'},
    );
    await t.pumpWidget(
      MaterialApp(home: SourceDiagnosticsPage(diagnostics: recorder)),
    );
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('source-diagnostics-export')),
      findsOneWidget,
    );
    expect(find.text('导出日志'), findsOneWidget);
    await t.scrollUntilVisible(
      find.textContaining('分类:'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('11:综合'), findsOneWidget);
    final error = t.takeException();
    if (error is FlutterError) {
      debugPrint(error.toDiagnosticsNode().toStringDeep());
    }
    expect(error, isNull);
  });
}
