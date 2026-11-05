import 'test_helpers/official_source_fixture.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

class _InterruptedStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  void Function()? onWrite;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    final callback = onWrite;
    onWrite = null;
    callback?.call();
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  setUp(installSyntheticOfficialAsset);
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final website = Uri.parse(
    'https://hongguoduanju.com/passport/web/check_qrconnect/',
  );
  HongguoAccountCookies cookies() => HongguoAccountCookies()
    ..merge(website, [
      'sessionid=synthetic-session; Path=/; Secure; HttpOnly',
      'passport_csrf_token=synthetic-csrf; Path=/; Secure',
      'ttwid=synthetic-region; Path=/; Secure',
    ]);
  test('账号凭据只进入指定官方业务域，不外传登录CSRF与地区Cookie', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('one');
    await session.accept(cookies(), {
      'id': '1234567890123456789',
      'nickname': '合成账号',
    }, expectedRevision: session.revision);
    expect(
      session.headerFor(
        Uri.parse(
          'https://reading.snssdk.com/novel/player/multi_video_model/v1/',
        ),
      ),
      'sessionid=synthetic-session',
    );
    expect(
      session.headerFor(
        Uri.parse(
          'https://api5-normal-sinfonlinea.fqnovel.com/reading/user/info/v1/',
        ),
      ),
      'sessionid=synthetic-session',
    );
    for (final url in [
      'https://v5-reading-video.qznovelvod.com/video',
      'https://github.com/reading/test',
      'https://reading.snssdk.com.evil.test/reading/test',
      'http://reading.snssdk.com/reading/test',
      'https://reading.snssdk.com/other',
      'https://log.snssdk.com/service/2/device_register/',
      'https://api5-normal.fqnovel.com.evil.test/novel/player/multi_video_model/v1/',
      'https://api5-normal.fqnovel.com/unrelated',
    ]) {
      expect(session.headerFor(Uri.parse(url)), isEmpty);
    }
  });
  test('保留域与路径、应用Cookie删除，不接受其他域', () {
    final jar = cookies();
    jar.merge(website, [
      'sessionid=attacker; Domain=evil.test; Path=/',
      'scoped=one; Path=/passport; Secure',
    ]);
    expect(jar.websiteHeader(website), contains('scoped=one'));
    expect(
      jar.websiteHeader(Uri.parse('https://hongguoduanju.com/passport-other/')),
      isNot(contains('scoped=one')),
    );
    jar.merge(website, ['sessionid=gone; Max-Age=0; Path=/']);
    expect(jar.hasSession, isFalse);
    expect(jar.websiteHeader(Uri.parse('https://evil.test/')), isEmpty);
  });
  test('CSRF遵守官方域及路径，主Cookie缺失时使用default', () {
    final jar = HongguoAccountCookies()
      ..merge(website, [
        'passport_csrf_token_default=synthetic-default; Path=/; Secure',
        'passport_csrf_token=synthetic-main; Path=/passport/web; Secure',
      ]);
    expect(jar.csrf, 'synthetic-main');
    expect(
      jar.csrfFor(
        Uri.parse('https://hongguoduanju.com/passport/account/info/'),
      ),
      'synthetic-default',
    );
    expect(
      jar.csrfFor(Uri.parse('http://hongguoduanju.com/passport/web/')),
      isEmpty,
    );
    expect(jar.csrfFor(Uri.parse('https://evil.test/passport/web/')), isEmpty);
    jar.merge(website, [
      'passport_csrf_token=; Max-Age=0; Path=/passport/web; Secure',
    ]);
    expect(jar.csrf, 'synthetic-default');
    expect(jar.businessHeader, isEmpty);
  });
  test('不同本地用户隔离，退出后迟到登录不能重新写入', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('one');
    await session.accept(cookies(), {
      'id': '123',
      'nickname': '合成',
    }, expectedRevision: session.revision);
    await session.bindProfile('two');
    expect(session.loggedIn, isFalse);
    await session.bindProfile('one');
    expect(session.loggedIn, isTrue);
    expect(session.verified, isFalse);
    final revision = session.revision;
    await session.logout();
    await expectLater(
      session.accept(cookies(), {'id': '456'}, expectedRevision: revision),
      throwsA(isA<HongguoAccountFailure>()),
    );
    await session.bindProfile('two');
    await session.bindProfile('one');
    expect(session.loggedIn, isFalse);
  });
  test('安全存储写入中取消恢复原值，不发布或残留候选账号', () async {
    final storage = _InterruptedStorage();
    final session = HongguoAccountSession(storage: storage);
    await session.bindProfile('interrupted');
    await session.accept(cookies(), {
      'id': '123',
    }, expectedRevision: session.revision);
    final previous = Map<String, String>.from(storage.values);
    var active = true;
    storage.onWrite = () => active = false;
    await expectLater(
      session.accept(
        cookies(),
        {'id': '456'},
        expectedRevision: session.revision,
        isCurrent: () => active,
      ),
      throwsA(isA<HongguoAccountFailure>()),
    );
    expect(session.id, '123');
    expect(storage.values, previous);
    await session.bindProfile('another');
    await session.bindProfile('interrupted');
    expect(session.id, '123');
  });
  test('官方源的扫码契约与大整数账号解析不依赖实际账号', () async {
    final source = await rootBundle.loadString('assets/sources/hongguo.js');
    final runtime = CatPawJsRuntime();
    addTearDown(runtime.dispose);
    await runtime.init(source);
    final command = await runtime.accountRequest('qr', {});
    final url = Uri.parse(command['url'] as String);
    expect(url.host, 'hongguoduanju.com');
    expect(url.path, '/passport/web/get_qrcode/');
    expect(url.queryParameters['aid'], '513755');
    final account = runtime.accountParse(
      'profile',
      '{"code":0,"data":{"biz_user_id":7688558312157088793,"user_name":"合成账号"}}',
    );
    expect(account['id'], '7688558312157088793');
    expect(
      () => runtime.accountParse('profile', '{"code":1,"data":{}}'),
      throwsA(isA<HongguoAccountFailure>()),
    );
    expect(
      () => runtime.accountParse(
        'poll',
        '{"message":"error","data":{"error_code":1102,"description":"synthetic"}}',
      ),
      throwsA(
        isA<HongguoAccountFailure>().having(
          (failure) => failure.code,
          'business code',
          'BUSINESS_1102',
        ),
      ),
    );
  });
  test('短信业务1102不冒充图形验证，二次验证不自动重发', () async {
    final runtime = CatPawJsRuntime();
    addTearDown(runtime.dispose);
    await runtime.init(
      await rootBundle.loadString('assets/sources/hongguo.js'),
    );
    expect(
      () => runtime.accountParse(
        'phoneCode',
        '{"message":"error","data":{"error_code":1102}}',
      ),
      throwsA(
        isA<HongguoAccountFailure>().having(
          (v) => v.code,
          'code',
          'BUSINESS_1102',
        ),
      ),
    );
    expect(
      () => runtime.accountParse(
        'phoneCode',
        '{"message":"error","data":{"error_code":1105,"verify_center_secondary_decision_conf":{"code":20000}}}',
      ),
      throwsA(
        isA<HongguoAccountFailure>().having(
          (v) => v.code,
          'code',
          'SECONDARY_VERIFICATION_REQUIRED',
        ),
      ),
    );
    expect(
      runtime.accountParse(
        'phoneCode',
        '{"message":"success","data":{"retry_time":60,"verify_center_decision_conf":{"code":10000}}}',
      )['verification'],
      isNull,
    );
  });
  test('仅自报官方源id不能获得账号能力', () async {
    final runtime = CatPawJsRuntime();
    addTearDown(runtime.dispose);
    await runtime.init(
      'var spider={meta:{id:"hongguo"},accountRequest:function(){return {};}};',
    );
    await expectLater(
      runtime.accountRequest('qr', {}),
      throwsA(isA<HongguoAccountFailure>()),
    );
  });
  test('登录搜索携带同一账号与绑定设备，账号切换丢弃在途响应', () async {
    SharedPreferences.setMockInitialValues({});
    final session = HongguoAccountSession.shared;
    await session.bindProfile('synthetic-runtime-account');
    await session.accept(
      cookies(),
      {'id': '123', 'nickname': 'synthetic'},
      expectedRevision: session.revision,
      device: jsonEncode({
        'iid': '7345678901234567200',
        'device_id': '7345678901234567100',
      }),
    );
    addTearDown(session.logout);
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.path, '/reading/bookapi/search/tab/v');
      expect(request.headers['Cookie'], 'sessionid=synthetic-session');
      expect(request.url.queryParameters['user_is_login'], '1');
      expect(request.url.queryParameters['device_id'], '7345678901234567100');
      if (requests == 2) await session.logout();
      return http.Response(
        jsonEncode({
          'code': 0,
          'search_tabs': [
            {
              'tab_type': 29,
              'has_more': false,
              'next_offset': 0,
              'data': [
                {
                  'video_data': [
                    {
                      'series_id': '7345678901234567000',
                      'title': 'synthetic',
                      'episode_cnt': 1,
                    },
                  ],
                },
              ],
            },
          ],
        }),
        200,
      );
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(
      await rootBundle.loadString('assets/sources/hongguo.js'),
    );
    final profileRequest = await runtime.accountRequest('profile', {});
    final profileUrl = Uri.parse(profileRequest['url'] as String);
    expect(profileUrl.host, 'api5-normal-sinfonlinea.fqnovel.com');
    expect(profileUrl.path, '/reading/user/info/v1/');
    expect(profileUrl.queryParameters['device_id'], '7345678901234567100');
    expect(profileRequest['headers'], contains('x-medusa'));
    expect((await runtime.search('synthetic-one')).list, hasLength(1));
    await expectLater(
      runtime.search('synthetic-two'),
      throwsA(isA<Exception>()),
    );
    expect(requests, 2);
  });

  test('四条取流线路与记忆备用线路均携带账号，CDN不接收账号', () async {
    SharedPreferences.setMockInitialValues({});
    final session = HongguoAccountSession.shared;
    await session.bindProfile('synthetic-account-fallback');
    await session.accept(
      cookies(),
      {'id': '123'},
      expectedRevision: session.revision,
      device: jsonEncode({
        'iid': '7345678901234567200',
        'device_id': '7345678901234567100',
      }),
    );
    addTearDown(session.logout);
    final hosts = <String>[];
    final accountAttached = <bool>[];
    final mediaAccountAttached = <bool>[];
    const media = 'https://fixture.qznovelvod.com/account-fallback.mp4';
    final client = MockClient((request) async {
      if (request.url.host == 'fixture.qznovelvod.com') {
        mediaAccountAttached.add((request.headers['Cookie'] ?? '').isNotEmpty);
        return http.Response('', 200, headers: {'content-type': 'video/mp4'});
      }
      hosts.add(request.url.host);
      accountAttached.add(
        request.headers['Cookie'] == 'sessionid=synthetic-session',
      );
      if (request.url.host != 'api5-normal.fqnovel.com') {
        return http.Response('', 200);
      }
      final payload = jsonDecode(request.body) as Map;
      final videoId = payload['mixed_video_id_map']['1004'][0] as String;
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            videoId: {
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
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final runtime = CatPawJsRuntime(client);
    addTearDown(runtime.dispose);
    addTearDown(client.close);
    await runtime.init(
      await rootBundle.loadString('assets/sources/hongguo.js'),
    );
    expect(
      (await runtime.play('', '7345678901234567123_7345678901234568456')).url,
      media,
    );
    expect(
      (await runtime.play('', '7345678901234567123_7345678901234568457')).url,
      media,
    );
    expect(hosts, [
      'api5-normal-sinfonlineb.fqnovel.com',
      'reading.snssdk.com',
      'reading.snssdk.com',
      'api5-normal.fqnovel.com',
      'api5-normal.fqnovel.com',
    ]);
    expect(accountAttached, everyElement(isTrue));
    expect(mediaAccountAttached, isNotEmpty);
    expect(mediaAccountAttached, everyElement(isFalse));
  });
}
