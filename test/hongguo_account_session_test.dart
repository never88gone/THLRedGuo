import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';

void main() {
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
}
