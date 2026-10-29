import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

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
  final searchDevices = <String>[];
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
      searchDevices.add(r.url.queryParameters['device_id'] ?? '');
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
    await runtime.init(
      await rootBundle.loadString('assets/sources/hongguo.js'),
    );
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

  test('empty response preserves restored guest and library storage', () async {
    final saved = guest(oldDevice);
    f.sessions.resetForTesting(saved, f.time);
    expect((await f.play(await f.runtime())).errorCode, 'EMPTY_RESPONSE');
    expect(f.registrations, 0);
    expect(f.models, 4);
    expect(f.sessions.value, saved);
    expect(f.sessions.createdAt, f.time);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saved_favorites'), 'keep-favorites');
    expect(prefs.getString('saved_history'), 'keep-history');
  });

  test(
    'empty response after eleven minutes retains the active identity',
    () async {
      f.sessions.resetForTesting();
      final rt = await f.runtime();
      expect((await f.play(rt)).url, isNotEmpty);
      final saved = f.sessions.value;
      f.time = f.time.add(const Duration(minutes: 11));
      f.expireFirst = true;
      expect((await f.refresh(rt)).errorCode, 'EMPTY_RESPONSE');
      expect(f.registrations, 1);
      expect(f.sessions.value, saved);
      f.expireFirst = false;
      expect((await f.refresh(rt)).url, isNotEmpty);
      expect(f.registrations, 1);
      expect(f.modelIds.toSet(), {'7345678901234567101'});
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

  test('temporary rejection recovers using the same active guest', () async {
    f.sessions.resetForTesting();
    final rt = await f.runtime();
    await f.play(rt);
    final saved = f.sessions.value;
    f.time = f.time.add(const Duration(seconds: 30));
    f.empty = true;
    expect((await f.refresh(rt)).errorCode, 'EMPTY_RESPONSE');
    f.empty = false;
    expect((await f.refresh(rt)).url, isNotEmpty);
    expect(f.registrations, 1);
    expect(f.sessions.value, saved);
    expect(f.modelIds.toSet(), {'7345678901234567101'});
  });

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
      expect(f.registrations, 0);
      expect(f.models, 12);
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
    'parallel playback and preload share one registration and retain episode IDs',
    () async {
      f.sessions.resetForTesting();
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

  test('search cursor survives a temporary model failure', () async {
    f.sessions.resetForTesting(guest('7345678901234567109'));
    final rt = await f.runtime();
    expect((await rt.search('合成剧')).hasMore, true);
    f.empty = true;
    expect((await f.play(rt)).errorCode, 'EMPTY_RESPONSE');
    f.empty = false;
    expect((await f.play(rt)).url, isNotEmpty);
    expect((await rt.search('合成剧', page: 2)).list, isNotEmpty);
    expect(f.searchOffsets, ['0', '6']);
    expect(f.registrations, 0);
  });

  test(
    'new persisted guest is adopted before the first model request and preserves search cursor',
    () async {
      f.sessions.resetForTesting();
      final rt = await f.runtime();
      expect((await rt.search('合成剧')).hasMore, true);
      await f.sessions.pendingWrites;
      f.expireFirst = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        HongguoGuestSession.sessionKey,
        guest('7345678901234567109'),
      );
      await prefs.setInt(
        HongguoGuestSession.createdKey,
        f.time.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      );
      expect((await f.play(rt)).url, isNotEmpty);
      expect(f.modelIds, ['7345678901234567109']);
      expect(f.registrations, 1);
      expect((await rt.search('合成剧', page: 2)).list, isNotEmpty);
      expect(f.searchOffsets, ['0', '6']);
    },
  );

  test(
    'search adopts an externally updated guest without restarting pagination',
    () async {
      f.sessions.resetForTesting();
      final rt = await f.runtime();
      expect((await rt.search('合成剧')).hasMore, true);
      await f.sessions.pendingWrites;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        HongguoGuestSession.sessionKey,
        guest('7345678901234567109'),
      );
      await prefs.setInt(
        HongguoGuestSession.createdKey,
        f.time.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      );
      expect((await rt.search('合成剧', page: 2)).list, isNotEmpty);
      expect(f.searchDevices, ['7345678901234567101', '7345678901234567109']);
      expect(f.searchOffsets, ['0', '6']);
      expect(f.models, 0);
      expect(f.registrations, 1);
    },
  );

  test('older persisted guest cannot roll back a current session', () async {
    final current = guest('7345678901234567109');
    f.sessions.resetForTesting(current, f.time);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(HongguoGuestSession.sessionKey, guest(oldDevice));
    await prefs.setInt(
      HongguoGuestSession.createdKey,
      f.time.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    );
    expect(await f.sessions.refresh(), false);
    expect(f.sessions.value, current);
  });

  test(
    'a completed timestamp write updates current runtime diagnostics',
    () async {
      f.sessions.resetForTesting();
      final rt = await f.runtime();
      await rt.search('合成剧');
      await f.sessions.pendingWrites;
      final initial = f.time;
      f.time = initial.add(const Duration(seconds: 10));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        HongguoGuestSession.createdKey,
        initial.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
      );
      expect((await f.play(rt)).url, isNotEmpty);
      expect(f.recorder.entries.last.sessionStatus, contains('创建距今：5秒'));
      expect(f.registrations, 1);
    },
  );

  test('failed model recovery cannot adopt an older persisted guest', () async {
    final current = guest('7345678901234567109');
    f.sessions.resetForTesting(current, f.time);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(HongguoGuestSession.sessionKey, guest(oldDevice));
    await prefs.setInt(
      HongguoGuestSession.createdKey,
      f.time.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    );
    f.empty = true;
    expect((await f.play(await f.runtime())).errorCode, 'EMPTY_RESPONSE');
    expect(f.sessions.value, current);
    expect(f.models, 4);
    expect(f.registrations, 0);
  });

  test(
    'refresh waits for a pending session write before reading storage',
    () async {
      final current = guest('7345678901234567109');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(HongguoGuestSession.sessionKey, guest(oldDevice));
      f.sessions.accept(current);
      expect(await f.sessions.refresh(), false);
      expect(f.sessions.value, current);
      expect(prefs.getString(HongguoGuestSession.sessionKey), current);
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
    'cancelling a waiting runtime does not interrupt shared initialization',
    () async {
      f.sessions.resetForTesting();
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
  test(
    'cold parallel runtimes share one registration before playback',
    () async {
      f.sessions.resetForTesting();
      f.registrationStarted = Completer<void>();
      f.releaseRegistration = Completer<void>();
      final a = await f.runtime(), b = await f.runtime();
      final first = f.play(a);
      await f.registrationStarted!.future;
      final second = f.play(b, '7345678901234568457');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(f.registrations, 1);
      f.releaseRegistration!.complete();
      final results = await Future.wait([first, second]);
      expect(results.every((r) => r.url.isNotEmpty), true);
      expect(f.registrations, 1);
      expect(f.modelIds.toSet(), {'7345678901234567101'});
    },
  );
}
