import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  final script = File('assets/sources/hongguo.js').readAsStringSync();
  for (final batch in [0, 6, 24, -1]) {
    final full = batch != 0;
    final count = batch > 0 ? batch : 6;
    test('TV batch=$batch fills the viewport and preserves cursor', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        if (request.url.path == '/service/2/device_register/') {
          return http.Response(
            '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
            200,
          );
        }
        requests.add(request.url);
        Map<String, dynamic> cell(
          int offset,
          int count, {
          bool selectors = false,
        }) => {
          'cell_id_str': 'synthetic',
          'next_offset': offset + count,
          'has_more': true,
          'session_id': 'synthetic-session',
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
          'cell_data': [
            {
              'video_data': [
                for (var i = offset; i < offset + count; i++)
                  {
                    'series_id': '7688558312157088${100 + i}',
                    'title': '合成剧$i',
                    'episode_cnt': 20,
                  },
              ],
            },
          ],
        };
        Object data;
        if (request.url.path.endsWith('/bookmall/tab/v')) {
          data = {
            'tab_item': [
              {
                'tab_type': 8,
                'cell_data': [cell(0, 6, selectors: true)],
              },
            ],
          };
        } else {
          expect(request.url.path, '/reading/bookapi/bookmall/cell/change/v');
          expect(request.url.queryParameters['limit'], '40');
          if (batch < 0 && requests.length == 2) {
            return http.Response(
              '{"code":500,"message":"synthetic failure"}',
              200,
            );
          }
          final offset = int.parse(request.url.queryParameters['offset']!);
          data = {
            'cell_view': cell(offset, count),
            'next_offset': offset + count,
            'has_more': true,
            'session_id': 'synthetic-session',
          };
        }
        return http.Response(
          jsonEncode({'code': 0, 'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final runtime = CatPawJsRuntime(client);
      addTearDown(runtime.dispose);
      await runtime.init(script);
      final first = await runtime.category(
        'app:discover:all',
        1,
        extend: full ? {'initialBatch': 12} : {},
      );
      expect(first.list, hasLength(batch > 0 ? 6 + count : 6));
      expect(requests, hasLength(full ? 2 : 1));
      if (full) {
        final second = await runtime.category(
          'app:discover:all',
          2,
          extend: {'initialBatch': 12},
        );
        expect(second.list, hasLength(count));
        expect(
          requests.last.queryParameters['offset'],
          '${batch > 0 ? 6 + count : 6}',
        );
        expect(
          first.list
              .map((e) => e['vod_id'])
              .toSet()
              .intersection(second.list.map((e) => e['vod_id']).toSet()),
          isEmpty,
        );
      }
    });
  }
}
