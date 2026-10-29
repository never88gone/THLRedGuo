import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/hongguo_guest_session.dart';

const oldDevice = '7335678901234567100';
const series = '7345678901234567000';
const video = '7345678901234568456';
String guest(String device) => jsonEncode({
  'device_id': device,
  'iid': '7345678901234567200',
  'cdid': '11111111-1111-4111-8111-111111111111',
});

class Fixture {
  DateTime time = DateTime(2026, 10, 29, 2);
  late final sessions = HongguoGuestSession(now: () => time);
  late final client = MockClient(request);
  final recorder = SourceDiagnostics();
  int registrations = 0;
  int models = 0;
  int denial = 200;
  int mediaStatus = 200;
  int mediaProbes = 0;
  int? modelExpiresAt;
  bool empty = false;
  bool expireFirst = false;
  Future<void> Function()? onFourthEmpty;
  Completer<void>? registrationStarted;
  Completer<void>? releaseRegistration;
  final modelIds = <String>[];
  final searchOffsets = <String>[];
  final runtimes = <CatPawJsRuntime>[];

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> request(http.Request r) async {
    if (r.url.path.contains('device_register')) {
      registrations++;
      if (registrationStarted?.isCompleted == false) {
        registrationStarted!.complete();
      }
      if (releaseRegistration != null) await releaseRegistration!.future;
      return json({
        'device_id_str': '734567890123456710$registrations',
        'install_id_str': '7345678901234567200',
      });
    }
    if (r.method == 'HEAD') {
      mediaProbes++;
      return http.Response(
        '',
        mediaStatus,
        headers: {'content-type': 'video/mp4'},
      );
    }
    if (r.url.path.contains('search/tab/v')) {
      final offset = r.url.queryParameters['offset']!;
      searchOffsets.add(offset);
      if (offset != '0') {
        expect(r.url.queryParameters['passback'], 'sticky-cursor');
      }
      return json({
        'code': 0,
        'search_tabs': [
          {
            'tab_type': 29,
            'title': '剧集',
            'has_more': offset == '0',
            'next_offset': 6,
            'passback': 'sticky-cursor',
            'search_id': 'synthetic-search',
            'data': [
              {
                'video_data': [
                  {
                    'series_id': offset == '0' ? series : '7345678901234567001',
                    'title': '合成剧',
                    'episode_cnt': 30,
                  },
                ],
              },
            ],
          },
        ],
      });
    }
    expect(r.url.path, contains('video_model'));
    models++;
    final device = r.url.queryParameters['device_id'];
    modelIds.add(device ?? '');
    final bad =
        device == oldDevice ||
        empty ||
        expireFirst && device == '7345678901234567101';
    if (bad || denial != 200) {
      if (models == 4 && onFourthEmpty != null) await onFourthEmpty!();
      return http.Response('', denial);
    }
    final body = jsonDecode(r.body) as Map;
    final ids = body['video_id'] != null
        ? [body['video_id']]
        : (body['mixed_video_id_map'] as Map)['1004'] as List;
    final entries = {
      for (final id in ids)
        '$id': {
          if (modelExpiresAt != null) 'expire_time': modelExpiresAt,
          'video_model': {
            'video_list': {
              'main': {
                'codec_type': 'h264',
                'vwidth': 1080,
                'vheight': 1920,
                'main_url': base64Encode(
                  utf8.encode('https://fixture.qznovelvod.com/$id.mp4'),
                ),
              },
            },
          },
        },
    };
    return json({
      'code': 0,
      'data': body['video_id'] != null ? entries[ids.single] : entries,
    });
  }

  Future<CatPawJsRuntime> runtime() async {
    final runtime = CatPawJsRuntime.configured(
      client: client,
      recorder: recorder,
      guestSessions: sessions,
    );
    runtimes.add(runtime);
    await runtime.init(File('assets/sources/hongguo.js').readAsStringSync());
    return runtime;
  }

  Future<CatPawPlayResult> play(CatPawJsRuntime runtime, [String id = video]) =>
      runtime.play('', 'https://hongguoduanju.com/player/$series/$id');

  Future<CatPawPlayResult> refresh(CatPawJsRuntime runtime) => runtime.play(
    '',
    'https://hongguoduanju.com/player/$series/$video',
    flags: [
      {'avoidUrl': 'https://fixture.qznovelvod.com/$video.mp4'},
    ],
  );

  Future<void> close() async {
    for (final rt in runtimes) {
      rt.dispose();
    }
    await sessions.pendingWrites;
    client.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Fixture f;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'saved_favorites': 'keep-favorites',
      'saved_history': 'keep-history',
    });
    f = Fixture();
  });
  tearDown(() async => f.close());

  test(
    'restored rejected guest renews once and preserves library storage',
    () async {
      f.sessions.resetForTesting(guest(oldDevice));
      expect((await f.play(await f.runtime())).url, contains(video));
      expect(f.registrations, 1);
      expect(f.models, 5);
      expect(
        f.recorder.entries.where((e) => e.stage == '游客会话恢复'),
        hasLength(1),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_favorites'), 'keep-favorites');
      expect(prefs.getString('saved_history'), 'keep-history');
      expect(
        prefs.getString(HongguoGuestSession.sessionKey),
        isNot(guest(oldDevice)),
      );
    },
  );

  test(
    'new active guest expires after successful playback and renews',
    () async {
      f.sessions.resetForTesting();
      final rt = await f.runtime();
      expect((await f.play(rt)).url, isNotEmpty);
      f.time = f.time.add(const Duration(minutes: 11));
      f.expireFirst = true;
      final result = await f.refresh(rt);
      expect(
        result.url,
        contains(video),
        reason: jsonEncode({
          'registrations': f.registrations,
          'models': f.models,
          'created': f.sessions.createdAt?.toIso8601String(),
          'trace': f.recorder.entries
              .map(
                (e) => {
                  'stage': e.stage,
                  'code': e.errorCode,
                  'session': e.sessionStatus,
                },
              )
              .toList(),
        }),
      );
      expect(f.registrations, 2);
      expect(f.models, 6);
    },
  );

  test(
    'official six-hour model expiry produces a bounded five-minute plan',
    () async {
      f.sessions.resetForTesting();
      final began = DateTime.now().millisecondsSinceEpoch;
      f.modelExpiresAt = began ~/ 1000 + 21600;
      final result = await f.play(await f.runtime());
      expect(result.url, isNotEmpty);
      expect(
        result.expiresAt,
        inInclusiveRange(began + 295000, began + 310000),
      );
    },
  );

  test(
    'near-expired official media is not prolonged or treated as a new guest',
    () async {
      f.sessions.resetForTesting();
      f.modelExpiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
      final result = await f.play(await f.runtime());
      expect(result.errorCode, 'MEDIA_URL_EXPIRED');
      expect(f.registrations, 1);
      expect(f.mediaProbes, 0);
      expect(f.models, lessThanOrEqualTo(2));
    },
  );

  test(
    'CDN rejection preserves the guest and bounds model refreshes',
    () async {
      f.sessions.resetForTesting();
      f.mediaStatus = 403;
      final result = await f.play(await f.runtime());
      expect(result.errorCode, 'MEDIA_HTTP_403');
      expect(f.registrations, 1);
      expect(f.models, lessThanOrEqualTo(2));
      expect(f.mediaProbes, lessThanOrEqualTo(2));
    },
  );

  test(
    'previously working guest can recover before ten minutes without churn',
    () async {
      f.sessions.resetForTesting();
      final rt = await f.runtime();
      await f.play(rt);
      f.time = f.time.add(const Duration(seconds: 30));
      f.expireFirst = true;
      expect((await f.refresh(rt)).url, isNotEmpty);
      expect(f.registrations, 2);
      f.empty = true;
      expect((await f.refresh(rt)).errorCode, 'EMPTY_RESPONSE');
      expect(f.registrations, 2);
      expect(
        f.recorder.report(version: '1.0.0', sourceHash: 'synthetic'),
        contains('成功取流：1次'),
      );
    },
  );

  test(
    'a fresh guest that never played is not repeatedly registered',
    () async {
      f.sessions.resetForTesting();
      f.empty = true;
      final rt = await f.runtime();
      expect((await f.play(rt)).errorCode, 'EMPTY_RESPONSE');
      expect(f.registrations, 1);
      expect(f.models, 4);
      expect(f.recorder.entries.where((e) => e.stage == '游客会话恢复'), isEmpty);
    },
  );

  test(
    'persistent empty response remains bounded across runtime reloads',
    () async {
      f.sessions.resetForTesting(guest(oldDevice));
      f.empty = true;
      final rt = await f.runtime();
      for (final target in [rt, rt, await f.runtime()]) {
        expect((await f.play(target)).errorCode, 'EMPTY_RESPONSE');
      }
      expect(f.registrations, 1);
      expect(f.models, 16);
    },
  );

  for (final status in [403, 429]) {
    test('explicit HTTP $status never replaces the guest', () async {
      f.sessions.resetForTesting(guest(oldDevice));
      f.denial = status;
      expect((await f.play(await f.runtime())).errorCode, 'HTTP_$status');
      expect(f.registrations, 0);
      expect(f.models, 1);
    });
  }

  test(
    'parallel playback and preload share one renewal and retain episode IDs',
    () async {
      f.sessions.resetForTesting(guest(oldDevice));
      final a = await f.runtime(), b = await f.runtime();
      final plans = await Future.wait([
        f.play(a),
        f.play(b, '7345678901234568457'),
      ]);
      expect(plans[0].url, contains(video));
      expect(plans[1].url, contains('7345678901234568457'));
      expect(f.registrations, 1);
    },
  );

  test(
    'search cursor survives guest recovery in the same JS context',
    () async {
      f.sessions.resetForTesting(guest(oldDevice));
      final rt = await f.runtime();
      expect((await rt.search('合成剧')).hasMore, true);
      expect((await f.play(rt)).url, isNotEmpty);
      expect((await rt.search('合成剧', page: 2)).list, isNotEmpty);
      expect(f.searchOffsets, ['0', '6']);
    },
  );

  test(
    'latest guest from another isolate is adopted without registration',
    () async {
      f.sessions.resetForTesting(guest(oldDevice));
      f.onFourthEmpty = () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          HongguoGuestSession.sessionKey,
          guest('7345678901234567109'),
        );
        await prefs.setInt(
          HongguoGuestSession.createdKey,
          f.time.millisecondsSinceEpoch,
        );
      };
      expect((await f.play(await f.runtime())).url, isNotEmpty);
      expect(f.registrations, 0);
      expect(f.modelIds.last, '7345678901234567109');
    },
  );

  test(
    'cancelling a waiting runtime does not block on another renewal',
    () async {
      f.sessions.resetForTesting(guest(oldDevice));
      f.registrationStarted = Completer<void>();
      f.releaseRegistration = Completer<void>();
      final a = await f.runtime(), b = await f.runtime();
      final first = f.play(a);
      await f.registrationStarted!.future;
      final waiting = f.play(b);
      b.cancelPending();
      await expectLater(
        waiting.timeout(const Duration(seconds: 1)),
        throwsA(
          isA<CatPawSourceFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      f.releaseRegistration!.complete();
      expect((await first).url, isNotEmpty);
      expect(f.registrations, 1);
    },
  );
}
