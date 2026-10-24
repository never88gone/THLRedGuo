import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  final script = File('assets/sources/hongguo.js').readAsStringSync();
  const ids = ['7688558312157088793', '7678338044344159256'];
  http.Response response(Object data) => http.Response(
    jsonEncode({'code': 0, 'data': data}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Map<String, Object?> cell(
    int index, {
    String cellId = 'synthetic',
    bool selectors = false,
  }) => {
    'cell_data': [],
    'cell_id_str': cellId,
    'next_offset': (index + 1) * 5,
    'has_more': true,
    'session_id': 'session-$index',
    if (selectors)
      'cell_selector': {
        'outer_row': {
          'items': [
            for (final genre in [
              'all',
              'playlet',
              'motion_comic',
              'ai_playlet',
            ])
              {
                'selector_item_id': genre,
                'show_name': genre,
                'is_selected': genre == 'all',
              },
          ],
        },
      },
    'video_data': [
      {
        'series_id': ids[index],
        'title': '合成短剧$index',
        'episode_cnt': 1,
        'video_detail': {
          'series_id_str': ids[index],
          'series_title': '合成短剧$index',
          'episode_cnt': 1,
          'video_list': [
            {'vid': ids[index], 'vid_index': 1},
          ],
        },
      },
    ],
  };
  for (final feed in [false, true]) {
    test(
      '${feed ? 'feed' : 'discovery'} publishes first nonempty response without filling a batch and resumes cursor',
      () async {
        var changes = 0;
        final client = MockClient((request) async {
          if (request.url.path == '/service/2/device_register/') {
            return http.Response(
              '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
              200,
            );
          }
          if (request.url.path.endsWith('/bookmall/tab/v')) {
            return response({
              'tab_item': [
                {
                  'tab_type': feed ? 16 : 8,
                  'bottom_unlimited': true,
                  'next_offset': 5,
                  'session_id': 'session-0',
                  'cell_data': [cell(0, selectors: !feed)],
                },
              ],
            });
          }
          expect(request.url.path, '/reading/bookapi/bookmall/cell/change/v');
          changes++;
          final q = request.url.queryParameters;
          expect(q['offset'], '5');
          expect(q['session_id'], 'session-0');
          return response({
            'cell_view': cell(1),
            'has_more': false,
            'next_offset': 10,
          });
        });
        final runtime = CatPawJsRuntime(client);
        addTearDown(runtime.dispose);
        addTearDown(client.close);
        await runtime.init(script);
        final first = feed
            ? await runtime.feed(1, 'latency_0')
            : await runtime.category('app:discover:all', 1);
        expect(first.list.map((e) => e['vod_id']), [ids[0]]);
        expect(first.hasMore, true);
        expect(changes, 0);
        final next = feed
            ? await runtime.feed(2, 'latency_0')
            : await runtime.category('app:discover:all', 2);
        expect(changes, 1);
        expect(next.list.map((e) => e['vod_id']), [ids[1]]);
        expect(next.hasMore, false);
      },
    );
    test(
      '${feed ? 'feed' : 'discovery'} skips duplicate-only response and uses latest cursor without losing later rows',
      () async {
        var changes = 0;
        final client = MockClient((request) async {
          if (request.url.path == '/service/2/device_register/') {
            return http.Response(
              '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
              200,
            );
          }
          if (request.url.path.endsWith('/bookmall/tab/v')) {
            return response({
              'tab_item': [
                {
                  'tab_type': feed ? 16 : 8,
                  'bottom_unlimited': true,
                  'next_offset': 5,
                  'session_id': 'session-0',
                  'cell_data': [cell(0, selectors: !feed)],
                },
              ],
            });
          }
          changes++;
          final q = request.url.queryParameters;
          if (changes == 1) {
            expect(q['offset'], '5');
            return response({
              'cell_view': cell(0, cellId: 'new-cell'),
              'has_more': true,
              'next_offset': 10,
              'session_id': 'new-session',
            });
          }
          expect(changes, 2);
          expect(q['offset'], '10');
          expect(q['cell_id'], 'new-cell');
          expect(q['session_id'], 'new-session');
          return response({
            'cell_view': cell(1),
            'has_more': false,
            'next_offset': 15,
          });
        });
        final runtime = CatPawJsRuntime(client);
        addTearDown(runtime.dispose);
        addTearDown(client.close);
        await runtime.init(script);
        if (feed) {
          await runtime.feed(1, 'cursor_0');
        } else {
          await runtime.category('app:discover:all', 1);
        }
        expect(changes, 0);
        final next = feed
            ? await runtime.feed(2, 'cursor_0')
            : await runtime.category('app:discover:all', 2);
        expect(next.list.map((e) => e['vod_id']), [ids[1]]);
        expect(changes, 2);
        expect(next.hasMore, false);
      },
    );
  }
  for (final feed in [false, true]) {
    test(
      '${feed ? 'feed' : 'discovery'} preserves retry cursor if skipping duplicates fails',
      () async {
        var fail = true;
        final offsets = <String>[];
        final client = MockClient((request) async {
          if (request.url.path == '/service/2/device_register/') {
            return http.Response(
              '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
              200,
            );
          }
          if (request.url.path.endsWith('/bookmall/tab/v')) {
            return response({
              'tab_item': [
                {
                  'tab_type': feed ? 16 : 8,
                  'bottom_unlimited': true,
                  'next_offset': 5,
                  'session_id': 'session-0',
                  'cell_data': [cell(0, selectors: !feed)],
                },
              ],
            });
          }
          expect(request.url.path, '/reading/bookapi/bookmall/cell/change/v');
          final offset = request.url.queryParameters['offset']!;
          offsets.add(offset);
          if (offset == '5') {
            return response({
              'cell_view': cell(0),
              'has_more': true,
              'next_offset': 10,
            });
          }
          if (fail) {
            fail = false;
            return http.Response('', 503);
          }
          return response({
            'cell_view': cell(1),
            'has_more': false,
            'next_offset': 15,
          });
        });
        final runtime = CatPawJsRuntime(client);
        addTearDown(runtime.dispose);
        addTearDown(client.close);
        await runtime.init(script);
        Future<CatPawCategoryResult> page(int value) => feed
            ? runtime.feed(value, 'retry_0')
            : runtime.category('app:discover:all', value);
        await page(1);
        await expectLater(page(2), throwsException);
        final next = await page(2);
        expect(next.list.single['vod_id'], ids[1]);
        expect(offsets, ['5', '10', '5', '10']);
      },
    );
  }
  test(
    'official discovery failure is retryable without falling back to an unrelated endpoint',
    () async {
      var fail = true;
      final offsets = <String>[];
      final client = MockClient((request) async {
        if (request.url.path == '/service/2/device_register/') {
          return http.Response(
            '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
            200,
          );
        }
        if (request.url.path.endsWith('/bookmall/tab/v')) {
          return response({
            'tab_item': [
              {
                'tab_type': 8,
                'cell_data': [cell(0, selectors: true)],
              },
            ],
          });
        }
        expect(request.url.path, '/reading/bookapi/bookmall/cell/change/v');
        offsets.add(request.url.queryParameters['offset']!);
        if (fail) {
          fail = false;
          return http.Response('', 503);
        }
        return response({
          'cell_view': cell(1),
          'has_more': false,
          'next_offset': 10,
        });
      });
      final runtime = CatPawJsRuntime(client);
      addTearDown(runtime.dispose);
      addTearDown(client.close);
      await runtime.init(script);
      await runtime.category('app:discover:all', 1);
      await expectLater(
        runtime.category('app:discover:all', 2),
        throwsException,
      );
      final next = await runtime.category('app:discover:all', 2);
      expect(next.list.single['vod_id'], ids[1]);
      expect(offsets, ['5', '5']);
    },
  );
}
