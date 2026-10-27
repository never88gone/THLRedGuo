import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  setUp(() => CatPawJsRuntime.resetDeviceSessionForTesting());
  final script = File('assets/sources/hongguo.js').readAsStringSync();
  const ids = [
    '7345678901234567000',
    '7345678901234567001',
    '7345678901234567002',
  ];
  Map<String, Object?> row(String id) => {
    'video_data': [
      {
        'series_id': int.parse(id),
        'title': '合成$id',
        'cover': 'https://images.example.test/blocked.heic',
        'episode_cnt': 80,
      },
    ],
  };
  http.Response page(
    List<Map<String, Object?>> rows, {
    bool more = false,
    int next = 0,
    String cursor = '',
  }) => http.Response(
    jsonEncode({
      'code': 0,
      'search_tabs': [
        {
          'tab_type': 29,
          'data': rows,
          'has_more': more,
          'next_offset': next,
          'passback': cursor,
          'search_id': 'synthetic-search',
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  http.Response registration() => http.Response(
    jsonEncode({
      'device_id_str': '7345678901234567100',
      'install_id_str': '7345678901234567200',
    }),
    200,
  );

  test('真实游标、去重、终页和匿名会话复用', () async {
    var registrations = 0;
    var searches = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/service/2/device_register/') {
        registrations++;
        final body = jsonDecode(request.body) as Map;
        expect(body['magic_tag'], 'ss_app_log');
        expect(
          (body['header'] as Map)['cdid'],
          matches(RegExp(r'^[0-9a-f-]{36}$')),
        );
        return registration();
      }
      expect(request.url.path, '/reading/bookapi/search/tab/v');
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(request.url.queryParameters['device_id'], '7345678901234567100');
      expect(request.url.queryParameters['tab_type'], '29');
      searches++;
      if (searches == 1) {
        return page(
          [row(ids[0])],
          more: true,
          next: 7,
          cursor: 'opaque/next+cursor',
        );
      }
      expect(request.url.queryParameters['offset'], '7');
      expect(request.url.queryParameters['passback'], 'opaque/next+cursor');
      expect(request.url.queryParameters['search_id'], 'synthetic-search');
      return page([row(ids[0]), row(ids[1])], next: 9);
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    final first = await runtime.search('含"引号\\及换行\n');
    final second = await runtime.search('含"引号\\及换行\n', page: 2);
    final cached = await runtime.search('含"引号\\及换行\n', page: 2);
    final end = await runtime.search('含"引号\\及换行\n', page: 3);
    expect(first.list.single['vod_id'], ids[0]);
    expect(first.hasMore, isTrue);
    expect(second.list.single['vod_id'], ids[1]);
    expect(second.hasMore, isFalse);
    expect(cached.list, second.list);
    expect(end.list, isEmpty);
    expect(registrations, 1);
    expect(searches, 2);
  });

  test('无结果、空关键词与服务端错误不会回退网页推荐', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (request.url.path == '/service/2/device_register/') {
        return registration();
      }
      expect(request.url.path, '/reading/bookapi/search/tab/v');
      if (request.url.queryParameters['query'] == '失败') {
        return http.Response('', 503);
      }
      return page([]);
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    expect((await runtime.search('  ')).list, isEmpty);
    expect(calls, 0);
    expect((await runtime.search('空结果')).hasMore, isFalse);
    expect((await runtime.search('空结果', page: 2)).list, isEmpty);
    expect(calls, 3);
    await expectLater(runtime.search('失败'), throwsA(isA<Exception>()));
  });

  test('不同关键词保持独立游标', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/service/2/device_register/') {
        return registration();
      }
      final q = request.url.queryParameters;
      final first = q['offset'] == '0';
      if (!first) expect(q['passback'], '${q['query']}-cursor');
      return page(
        [row(first ? ids[0] : ids[2])],
        more: first,
        next: first ? 12 : 20,
        cursor: '${q['query']}-cursor',
      );
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    await runtime.search('甲');
    await runtime.search('乙');
    expect((await runtime.search('甲', page: 2)).list.single['vod_id'], ids[2]);
    expect((await runtime.search('乙', page: 2)).list.single['vod_id'], ids[2]);
  });

  test('游标不推进时显式失败', () async {
    final client = MockClient(
      (request) async => request.url.path == '/service/2/device_register/'
          ? registration()
          : page([row(ids[0])], more: true, next: 0),
    );
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    await expectLater(runtime.search('停滞'), throwsA(isA<Exception>()));
  });

  test('拒绝没有字符串设备 ID 的注册响应', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/service/2/device_register/');
      return http.Response(
        '{"device_id":7345678901234567100,"install_id":7345678901234567200}',
        200,
      );
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(script);
    await expectLater(runtime.search('注册失败'), throwsA(isA<Exception>()));
  });
}
