import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/js/hongguo_guest_session.dart';
import 'package:THLRedLook/core/account/account_transfer_payload.dart';

class _Reply extends Stream<List<int>> implements HttpClientResponse {
  _Reply(this.payload, [List<String> cookies = const []])
    : headers = _Headers(cookies);
  final Object payload;
  @override
  final HttpHeaders headers;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(payload))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers([this.cookies = const []]);
  final List<String> cookies;
  final fields = <String, Object>{};
  @override
  List<String>? operator [](String name) =>
      name == HttpHeaders.setCookieHeader ? cookies : null;
  @override
  String? value(String name) => fields[name]?.toString();
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    fields[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.uri, this.respond);
  @override
  final Uri uri;
  final _Reply Function(Uri, _Headers) respond;
  @override
  final _Headers headers = _Headers();
  final bodyText = StringBuffer();
  @override
  void write(Object? object) => bodyText.write(object);
  @override
  bool followRedirects = true;
  bool aborted = false;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
  }

  @override
  Future<HttpClientResponse> close() async {
    if (bodyText.isNotEmpty) {
      headers.fields['synthetic-body'] = bodyText.toString();
    }
    return respond(uri, headers);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.respond);
  final _Reply Function(Uri, _Headers) respond;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(url, respond);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredClient extends _Client {
  _DeferredClient(super.respond);
  final opened = Completer<void>();
  final release = Completer<void>();
  late _Request pending;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    pending = _Request(url, respond);
    opened.complete();
    await release.future;
    return pending;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      HongguoGuestSession.sessionKey: jsonEncode({
        'iid': '7345678901234567200',
        'device_id': '7345678901234567100',
        'cdid': 'synthetic-device',
      }),
    });
  });
  test('传入账号先使用候选设备与轮转Cookie校验，提交前不覆盖当前账号', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('candidate-device');
    final candidate = AccountTransferPayload.decode(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'id': '123',
          'cookies': [
            {
              'name': 'sessionid',
              'value': 'synthetic-before',
              'domain': 'hongguoduanju.com',
              'path': '/',
              'expires': null,
            },
          ],
          'device': {
            'iid': '7345678901234567999',
            'device_id': '7345678901234567888',
            'cdid': 'synthetic-candidate',
          },
        }),
      ),
    );
    final service = HongguoAccountService(session: session);
    addTearDown(service.dispose);
    await HttpOverrides.runZoned(
      () async {
        final proof = await service.prepareTransferred(
          candidate,
          isCurrent: () => true,
        );
        expect(session.loggedIn, false);
        await service.commitTransferred(proof, isCurrent: () => true);
        expect(session.id, '123');
        expect(
          jsonDecode(session.deviceSession!)['device_id'],
          '7345678901234567888',
        );
      },
      createHttpClient: (_) => _Client((uri, headers) {
        if (uri.path == '/passport/account/info/v2/') {
          expect(headers.value('Cookie'), 'sessionid=synthetic-before');
          return _Reply(
            {'message': 'success', 'data': {}},
            ['sessionid=synthetic-rotated; Path=/; Secure'],
          );
        }
        expect(uri.path, '/reading/user/info/v1/');
        expect(uri.queryParameters['device_id'], '7345678901234567888');
        expect(headers.value('Cookie'), 'sessionid=synthetic-rotated');
        return _Reply({
          'code': 0,
          'data': {'biz_user_id': '123', 'user_name': '合成'},
        });
      }),
    );
  });
  test('轮询状态未到confirmed但已签发会话时完成App账号校验', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-flow');
    final paths = <String>[];
    await HttpOverrides.runZoned(
      () async {
        final service = HongguoAccountService(session: session);
        addTearDown(service.dispose);
        final login = await service.begin();
        expect(await service.poll(login), isTrue);
        expect(session.loggedIn, isTrue);
        expect(paths, [
          '/passport/web/get_qrcode/',
          '/passport/web/check_qrconnect/',
          '/passport/account/info/v2/',
          '/reading/user/info/v1/',
        ]);
      },
      createHttpClient: (_) => _Client((uri, headers) {
        paths.add(uri.path);
        if (uri.path.endsWith('/get_qrcode/')) {
          return _Reply({
            'message': 'success',
            'data': {
              'token': 'synthetic-token',
              'qrcode_index_url':
                  'https://reading.snssdk.com/reading_offline/novelread/page/scan-code.html?token=synthetic-token',
              'expire_time': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
            },
          });
        }
        if (uri.path.endsWith('/check_qrconnect/')) {
          return _Reply(
            {
              'message': 'success',
              'data': {'status': 'scanned'},
            },
            ['sessionid=synthetic-session; Path=/; Secure'],
          );
        }
        if (uri.path == '/passport/account/info/v2/') {
          return _Reply({'message': 'success', 'data': {}});
        }
        expect(headers.value('Cookie'), 'sessionid=synthetic-session');
        return _Reply({
          'code': 0,
          'data': {
            'biz_user_id': '1234567890123456789',
            'user_name': 'synthetic',
          },
        });
      }),
    );
  });
  test('账号校验暂时失败后复用已确认会话，不重查已消费二维码', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-retry');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-session; Path=/; Secure',
      ]);
    final login = HongguoQrLogin(
      'synthetic',
      DateTime.now().subtract(const Duration(seconds: 1)),
      'synthetic-token',
      cookies,
      session.revision,
    );
    var profileRequests = 0;
    await HttpOverrides.runZoned(
      () async {
        final service = HongguoAccountService(session: session);
        addTearDown(service.dispose);
        await expectLater(
          service.poll(login),
          throwsA(
            isA<HongguoAccountFailure>().having(
              (e) => e.code,
              'business code',
              'BUSINESS_15',
            ),
          ),
        );
        expect(login.confirmed, isTrue);
        expect(await service.poll(login), isTrue);
        expect(profileRequests, 2);
        expect(session.loggedIn, isTrue);
      },
      createHttpClient: (_) => _Client((uri, headers) {
        expect(uri.path, isNot('/passport/web/check_qrconnect/'));
        if (uri.path == '/passport/account/info/v2/') {
          return _Reply({'message': 'success', 'data': {}});
        }
        profileRequests++;
        if (profileRequests == 1) return _Reply({'code': 15, 'data': {}});
        return _Reply({
          'code': 0,
          'data': {
            'biz_user_id': '1234567890123456789',
            'user_name': 'synthetic',
          },
        });
      }),
    );
  });
  test('账号追剧和历史使用当前会话并补齐剧集资料，大整数和毫秒进度不丢失', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-library');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-library; Path=/; Secure',
      ]);
    await session.accept(cookies, {
      'id': '123',
      'nickname': '合成',
      'avatar': 'https://example.test/avatar',
    }, expectedRevision: session.revision);
    final service = HongguoAccountService(session: session);
    addTearDown(service.dispose);
    await HttpOverrides.runZoned(
      () async {
        final follows = await service.library(history: false);
        expect(follows.single.drama.cleanSourceId, '7688558312157088793');
        expect(follows.single.drama.title, '合成剧详情');
        final history = await service.library(history: true);
        expect(history.single.drama.title, '合成剧详情');
        expect(history.single.episode, 12);
        expect(history.single.position, 23.5);
        expect(history.single.duration, 90);
        expect(history.single.drama.episodes, 120);
        expect(history.single.updatedAt.millisecondsSinceEpoch, 1700000000000);
      },
      createHttpClient: (_) => _Client((uri, headers) {
        expect(headers.value('Cookie'), 'sessionid=synthetic-library');
        if (uri.path.contains('/bookshelf/')) {
          expect(uri.path, '/reading/bookapi/bookshelf/video/list/v1/');
          expect(uri.queryParameters['target_user_id'], '123');
          return _Reply({
            'code': 0,
            'data': {
              'video_shelf_info': [
                {
                  'series_id': '7688558312157088793',
                  'book_type': 2,
                  'collect_time': 1700000000,
                },
              ],
            },
          });
        }
        if (uri.path.contains('/read_progress/')) {
          expect(uri.queryParameters['limit'], '50');
          return _Reply({
            'code': 0,
            'data': null,
            'video_data': [
              {
                'series_id': '7688558312157088793',
                'vid': '1234567890123456789',
                'vid_index': 12,
                'current_play_time': 23500,
                'current_total_time': 90000,
                'last_watch_time': 1700000000,
              },
            ],
          });
        }
        expect(uri.path, '/reading/bookapi/multi-detail/v1/');
        expect(uri.queryParameters['book_id'], '7688558312157088793');
        return _Reply({
          'code': 0,
          'data': [
            {
              'book_id': '7688558312157088793',
              'book_name': '合成剧详情',
              'episode_cnt': 120,
            },
          ],
        });
      }),
    );
    await session.bindProfile('other');
    await session.bindProfile('synthetic-library');
    expect(session.avatar, 'https://example.test/avatar');
    await session.logout();
    expect(session.avatar, isEmpty);
  });
  test('账号列表格式改变和业务拒绝不能变成成功空列表', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-invalid-library');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-library; Path=/; Secure',
      ]);
    await session.accept(cookies, {
      'id': '123',
    }, expectedRevision: session.revision);
    final service = HongguoAccountService(session: session);
    addTearDown(service.dispose);
    await HttpOverrides.runZoned(
      () async {
        await expectLater(
          service.library(history: false),
          throwsA(isA<HongguoAccountFailure>()),
        );
        await expectLater(
          service.library(history: true),
          throwsA(isA<HongguoAccountFailure>()),
        );
      },
      createHttpClient: (_) => _Client(
        (uri, _) => _Reply(
          uri.path.contains('/bookshelf/')
              ? {'code': 0, 'data': {}}
              : {'code': 15, 'data': {}},
        ),
      ),
    );
  });
  test('切换账号期间已打开但未发送的请求不能附加新账号Cookie', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('synthetic-library-race');
    HongguoAccountCookies cookies(String token) => HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=$token; Path=/; Secure',
      ]);
    await session.accept(cookies('synthetic-a'), {
      'id': '123',
    }, expectedRevision: session.revision);
    var sent = 0;
    final client = _DeferredClient((_, _) {
      sent++;
      return _Reply({
        'code': 0,
        'data': {'video_shelf_info': []},
      });
    });
    await HttpOverrides.runZoned(() async {
      final service = HongguoAccountService(session: session);
      addTearDown(service.dispose);
      final result = expectLater(
        service.library(history: false),
        throwsA(
          isA<HongguoAccountFailure>().having(
            (e) => e.code,
            'code',
            'CANCELLED',
          ),
        ),
      );
      await client.opened.future;
      await session.logout();
      await session.accept(cookies('synthetic-b'), {
        'id': '456',
      }, expectedRevision: session.revision);
      client.release.complete();
      await result;
      expect(sent, 0);
      expect(client.pending.headers.value('Cookie'), isNull);
      expect(client.pending.aborted, true);
    }, createHttpClient: (_) => client);
  });
  String mix(String value) =>
      utf8.encode(value).map((v) => (v ^ 5).toRadixString(16)).join();
  test('验证码和密码使用官方POST协议，不自动注册；取得会话后才确认App账号', () async {
    for (final password in [false, true]) {
      final session = HongguoAccountSession();
      await session.bindProfile('phone-$password');
      final paths = <String>[];
      await HttpOverrides.runZoned(
        () async {
          final service = HongguoAccountService(session: session);
          addTearDown(service.dispose);
          final phone = service.phone('86', '13800138000');
          if (!password) {
            expect(await service.sendPhoneCode(phone), 60);
            expect(session.loggedIn, false);
            await expectLater(
              service.sendPhoneCode(phone),
              throwsA(isA<HongguoAccountFailure>()),
            );
          }
          await service.loginPhone(
            phone,
            code: password ? null : '654321',
            password: password ? 'synthetic-password' : null,
          );
          expect(session.loggedIn, true);
          expect(session.id, '1234567890123456789');
          expect(session.verified, true);
          expect(paths.where((p) => p.contains('mobile/register')), isEmpty);
        },
        createHttpClient: (_) => _Client((uri, headers) {
          paths.add(uri.path);
          if (uri.path.endsWith('/get_qrcode/')) {
            return _Reply(
              {
                'message': 'success',
                'data': {
                  'token': 'synthetic-token',
                  'qrcode_index_url':
                      'https://reading.snssdk.com/reading_offline/novelread/page/scan-code.html?token=synthetic-token',
                  'expire_time': 60,
                },
              },
              ['passport_csrf_token=synthetic-csrf; Path=/; Secure'],
            );
          }
          if (uri.path.contains('/passport/web/')) {
            expect(headers.value('x-tt-passport-csrf-token'), 'synthetic-csrf');
            final form = Uri.splitQueryString(headers.value('synthetic-body')!);
            expect(form['mix_mode'], '1');
            expect(form['fixed_mix_mode'], '1');
            if (uri.path.endsWith('/send_code/')) {
              expect(form['mobile'], mix('+86 13800138000'));
              expect(form['type'], mix('24'));
              return _Reply({
                'message': 'success',
                'data': {'retry_time': 60},
              });
            }
            if (password) {
              expect(uri.path, '/passport/web/user/login/');
              expect(form['account'], mix('13800138000'));
              expect(form['password'], mix('synthetic-password'));
            } else {
              expect(uri.path, '/passport/web/sms_login_only/');
              expect(form['mobile'], mix('+86 13800138000'));
              expect(form['code'], mix('654321'));
            }
            return _Reply(
              {'message': 'success', 'data': {}},
              ['sessionid=synthetic-phone-session; Path=/; Secure'],
            );
          }
          if (uri.path == '/passport/account/info/v2/') {
            return _Reply({'message': 'success', 'data': {}});
          }
          expect(headers.value('Cookie'), 'sessionid=synthetic-phone-session');
          return _Reply({
            'code': 0,
            'data': {
              'biz_user_id': '1234567890123456789',
              'user_name': 'synthetic',
            },
          });
        }),
      );
    }
  });
  test('安全验证拒绝不自动重发短信，也不会把发送成功当作登录成功', () async {
    final session = HongguoAccountSession();
    await session.bindProfile('phone-challenge');
    var sent = 0;
    await HttpOverrides.runZoned(
      () async {
        final service = HongguoAccountService(session: session);
        addTearDown(service.dispose);
        await expectLater(
          service.sendPhoneCode(service.phone('86', '13800138000')),
          throwsA(
            isA<HongguoAccountFailure>().having(
              (v) => v.code,
              'code',
              'CHALLENGE_REQUIRED',
            ),
          ),
        );
        expect(sent, 1);
        expect(session.loggedIn, false);
      },
      createHttpClient: (_) => _Client((uri, _) {
        if (uri.path.endsWith('/get_qrcode/')) {
          return _Reply(
            {
              'message': 'success',
              'data': {
                'token': 'synthetic-token',
                'qrcode_index_url':
                    'https://reading.snssdk.com/reading_offline/novelread/page/scan-code.html?token=synthetic-token',
                'expire_time': 60,
              },
            },
            ['passport_csrf_token=synthetic-csrf; Path=/; Secure'],
          );
        }
        sent++;
        return _Reply({
          'message': 'error',
          'data': {'error_code': 1102, 'verify_center_decision_conf': {}},
        });
      }),
    );
  });
  test('二维码到期后的最终确认可接收已授权会话，最多查询一次', () async {
    for (final confirmed in [false, true]) {
      final session = HongguoAccountSession();
      await session.bindProfile('late-$confirmed');
      var polls = 0;
      await HttpOverrides.runZoned(
        () async {
          final service = HongguoAccountService(session: session);
          addTearDown(service.dispose);
          final login = HongguoQrLogin(
            'synthetic',
            DateTime.now().subtract(const Duration(seconds: 1)),
            'synthetic-token',
            HongguoAccountCookies(),
            session.revision,
          );
          expect(await service.poll(login, finalCheck: true), confirmed);
          if (!confirmed) {
            await expectLater(
              service.poll(login, finalCheck: true),
              throwsA(
                isA<HongguoAccountFailure>().having(
                  (v) => v.code,
                  'code',
                  'QR_EXPIRED',
                ),
              ),
            );
          }
          expect(polls, 1);
          expect(session.loggedIn, confirmed);
        },
        createHttpClient: (_) => _Client((uri, _) {
          if (uri.path.endsWith('/check_qrconnect/')) {
            polls++;
            return _Reply({
              'message': 'success',
              'data': {
                'status': confirmed ? 'confirmed' : 'new',
                'redirect_url': '',
              },
            }, confirmed ? ['sessionid=synthetic-late; Path=/; Secure'] : []);
          }
          if (uri.path == '/passport/account/info/v2/') {
            return _Reply({'message': 'success', 'data': {}});
          }
          return _Reply({
            'code': 0,
            'data': {
              'biz_user_id': '1234567890123456789',
              'user_name': 'synthetic',
            },
          });
        }),
      );
    }
  });
}
