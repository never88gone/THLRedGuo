import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/js/hongguo_guest_session.dart';

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
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => respond(uri, headers);
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
}
