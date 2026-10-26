import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
  const series = '7673742740500270105';
  final script = File('assets/sources/hongguo.js').readAsStringSync();
  final largeDescription = List.filled(18000, 'x').join();
  for (final cached in [false, true]) {
    test(
      '127 episodes and CDN headers survive old 100-episode cache=$cached',
      () async {
        var details = 0;
        final checked = <String>[];
        final client = MockClient((request) async {
          if (request.url.path == '/service/2/device_register/') {
            return http.Response(
              '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
              200,
            );
          }
          if (request.url.path == '/novel/player/video_detail/v1/') {
            details++;
            expect(request.url.host, 'reading.snssdk.com');
            expect(request.url.queryParameters['version_code'], '73932');
            expect(
              request.url.queryParameters['device_id'],
              isNot('7361909012345678901'),
            );
            expect(jsonDecode(request.body)['series_id'], series);
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {
                  'video_data': {
                    'series_id_str': series,
                    'series_title': '合成127集剧',
                    'episode_cnt': 127,
                    'video_list': [
                      for (var i = 1; i <= 127; i++)
                        {
                          'vid':
                              '7673744000000000${i.toString().padLeft(3, '0')}',
                          'vid_index': i,
                          if (cached) 'title': largeDescription,
                        },
                    ],
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(request.url.host, 'v95-aw-reading-video.qznovelvod.com');
          expect(request.method, 'HEAD');
          expect(
            request.headers.keys.any((k) => k.toLowerCase() == 'referer'),
            false,
          );
          checked.add(request.url.path.split('/').last);
          return http.Response('', 200, headers: {'content-type': 'video/mp4'});
        });
        final runtime = CatPawJsRuntime(client);
        addTearDown(runtime.dispose);
        addTearDown(client.close);
        final seed = cached
            ? "globalThis.__hongguoDetailCache=new Map([['$series',{updated:Date.now(),data:{episode_cnt:127,video_list:Array.from({length:100},(_,i)=>({vid:'7673744000000000'+String(i+1).padStart(3,'0')}))}}]]);"
            : '';
        await runtime.init('''
$script
$seed
HongguoApp.fetchAppPlayUrl=async function(vid){return {variants:[{vid:vid,url:'https://v95-aw-reading-video.qznovelvod.com/video/'+vid,quality:'1080p',userAgent:'synthetic-app',referer:'https://novelquickapp.com/'}]}};
''');
        final detail = await runtime.detail(series);
        final entries = detail.vod['vod_play_url'].toString().split('#');
        expect(entries, hasLength(127));
        expect(details, 1);
        for (final number in [99, 100, 101, 102, 127]) {
          final plan = await runtime.play(
            '',
            entries[number - 1].split(r'$').last,
          );
          expect(plan.url, isNotEmpty);
          expect(
            plan.header.keys.any((key) => key.toLowerCase() == 'referer'),
            false,
          );
          expect(
            Uri.parse(plan.url).pathSegments.last,
            '7673744000000000${number.toString().padLeft(3, '0')}',
          );
        }
        expect(checked, hasLength(5));
      },
    );
  }
  test(
    'official detail failure does not silently use website episode data',
    () async {
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add(r.url.path);
        if (r.url.path == '/service/2/device_register/') {
          return http.Response(
            '{"device_id_str":"7345678901234567100","install_id_str":"7345678901234567200"}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(r.url.path, '/novel/player/video_detail/v1/');
        return http.Response(
          '{"code":500,"message":"synthetic unavailable"}',
          200,
        );
      });
      final runtime = CatPawJsRuntime(client);
      addTearDown(runtime.dispose);
      addTearDown(client.close);
      await runtime.init(script);
      await expectLater(runtime.detail(series), throwsA(anything));
      expect(paths.any((p) => p == '/detail'), false);
    },
  );
}
