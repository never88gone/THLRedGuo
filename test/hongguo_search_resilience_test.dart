import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  final script = File('assets/sources/hongguo.js').readAsStringSync();
  const ids = [
    '7345678901234567000',
    '7345678901234567001',
    '7345678901234567002',
  ];
  http.Response response(Object data) => http.Response(
    jsonEncode(data),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  http.Response registration() => response({
    'device_id_str': '7345678901234567100',
    'install_id_str': '7345678901234567200',
  });
  Map<String, Object?> row(String id) => {
    'video_data': [
      {'series_id': id, 'title': '合成剧', 'episode_cnt': 30},
    ],
  };
  Map<String, Object?> tab(
    int type, {
    List<Object?> rows = const [],
    bool more = false,
    int next = 0,
    String cursor = '',
  }) => {
    'tab_type': type,
    'title': type == 29
        ? '剧集'
        : type == 11
        ? '综合'
        : '小说',
    'data': rows,
    'has_more': more,
    'next_offset': next,
    'passback': cursor,
    'search_id': 'synthetic-search',
  };
  http.Response page(List<Object?> tabs) =>
      response({'code': 0, 'search_tabs': tabs});
  setUp(() => CatPawJsRuntime.resetDeviceSessionForTesting());

  test(
    'Taiwan response without drama tab falls back to general 11 and keeps its cursor',
    () async {
      final requests = <Uri>[];
      var registrations = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/service/2/device_register/') {
          registrations++;
          return registration();
        }
        requests.add(r.url);
        final q = r.url.queryParameters;
        if (q['tab_type'] == '29') return page([tab(11), tab(1), tab(2)]);
        expect(q['tab_type'], '11');
        if (q['offset'] == '0') {
          return page([
            tab(29),
            tab(
              11,
              rows: [row(ids[0])],
              more: true,
              next: 6,
              cursor: 'general-cursor',
            ),
          ]);
        }
        expect(q['offset'], '6');
        expect(q['passback'], 'general-cursor');
        return page([
          tab(11, rows: [row(ids[1])], next: 12),
          tab(29),
        ]);
      });
      final rt = CatPawJsRuntime(client);
      addTearDown(rt.dispose);
      addTearDown(client.close);
      await rt.init(script);
      final first = await rt.search('合成查询');
      final next = await rt.search('合成查询', page: 2);
      expect(first.list.single['vod_id'], ids[0]);
      expect(first.hasMore, true);
      expect(next.list.single['vod_id'], ids[1]);
      expect(next.hasMore, false);
      expect(requests.map((u) => u.queryParameters['tab_type']), [
        '29',
        '11',
        '11',
      ]);
      expect(registrations, 1);
    },
  );
  test('dedicated page never mixes rows from unrelated tab cursors', () async {
    final client = MockClient(
      (r) async => r.url.path == '/service/2/device_register/'
          ? registration()
          : page([
              tab(11, rows: [row(ids[1])], more: true, next: 99),
              tab(29, rows: [row(ids[0])], more: true, next: 7),
            ]),
    );
    final rt = CatPawJsRuntime(client);
    addTearDown(rt.dispose);
    addTearDown(client.close);
    await rt.init(script);
    expect((await rt.search('合成查询')).list.map((r) => r['vod_id']), [ids[0]]);
  });
  test(
    'missing drama and general rows is a diagnostic failure instead of healthy empty results',
    () async {
      var calls = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/service/2/device_register/') return registration();
        calls++;
        return page([tab(11), tab(1), tab(2)]);
      });
      final rt = CatPawJsRuntime(client);
      addTearDown(rt.dispose);
      addTearDown(client.close);
      await rt.init(script);
      await expectLater(
        rt.search('合成查询'),
        throwsA(
          isA<CatPawSourceFailure>().having(
            (e) => e.code,
            'code',
            'SEARCH_TAB_MISSING',
          ),
        ),
      );
      expect(calls, 2);
    },
  );
  test('real empty matches stay empty when the drama tab exists', () async {
    final client = MockClient(
      (r) async => r.url.path == '/service/2/device_register/'
          ? registration()
          : page([tab(11), tab(29)]),
    );
    final rt = CatPawJsRuntime(client);
    addTearDown(rt.dispose);
    addTearDown(client.close);
    await rt.init(script);
    final p = await rt.search('确实不存在的合成剧');
    expect(p.list, isEmpty);
    expect(p.hasMore, false);
  });
  test(
    'transient search connection failure retries once without guest re-registration',
    () async {
      var searches = 0;
      var registrations = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/service/2/device_register/') {
          registrations++;
          return registration();
        }
        if (++searches == 1) throw http.ClientException('Connection reset');
        return page([
          tab(29, rows: [row(ids[0])]),
        ]);
      });
      final rt = CatPawJsRuntime(client);
      addTearDown(rt.dispose);
      addTearDown(client.close);
      await rt.init(script);
      expect((await rt.search('合成查询')).list, hasLength(1));
      expect(searches, 2);
      expect(registrations, 1);
    },
  );
  test(
    'fallback HTTP failure is visible and can retry the same first page',
    () async {
      var fail = true;
      var calls = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/service/2/device_register/') return registration();
        calls++;
        if (r.url.queryParameters['tab_type'] == '29') return page([tab(1)]);
        if (fail) return http.Response('temporary', 503);
        return page([
          tab(11, rows: [row(ids[0])]),
        ]);
      });
      final rt = CatPawJsRuntime(client);
      addTearDown(rt.dispose);
      addTearDown(client.close);
      await rt.init(script);
      await expectLater(rt.search('合成查询'), throwsA(isA<Exception>()));
      expect(calls, 3);
      fail = false;
      expect((await rt.search('合成查询')).list, hasLength(1));
    },
  );
  test('HTTP 403 never tries unrelated hosts or loops registration', () async {
    var calls = 0;
    var registrations = 0;
    final client = MockClient((r) async {
      if (r.url.path == '/service/2/device_register/') {
        registrations++;
        return registration();
      }
      expect(r.url.host, 'reading.snssdk.com');
      calls++;
      return http.Response('Forbidden', 403);
    });
    final rt = CatPawJsRuntime(client);
    addTearDown(rt.dispose);
    addTearDown(client.close);
    await rt.init(script);
    await expectLater(rt.search('合成查询'), throwsA(isA<Exception>()));
    expect(calls, 1);
    expect(registrations, 1);
  });
}
