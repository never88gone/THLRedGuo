import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/account/hongguo_verification_sdk.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.body);
  @override
  final int statusCode;
  final String body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async {
    expect(followRedirects, false);
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected request mutation');
}

class _Client implements HttpClient {
  _Client(this.respond);
  final _Response Function(Uri) respond;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(respond(url));
  @override
  void close({bool force = false}) {
    expect(force, true);
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final source = 'window.verifySDK={};${' ' * 1024}';
  setUp(() => SourceDiagnostics.shared.clear());
  test('官方备用地址依次尝试，不跟随重定向、不附加账号头，拒绝超大正文', () async {
    final urls = <String>[], clients = <_Client>[];
    await HttpOverrides.runZoned(
      () async {
        expect(await HongguoVerificationSdk.download(), source);
        expect(urls, HongguoVerificationSdk.urls);
        expect(clients.every((v) => v.closed), true);
      },
      createHttpClient: (_) {
        final client = _Client((uri) {
          urls.add(uri.toString());
          return switch (urls.length) {
            1 => _Response(302, 'synthetic-private-redirect'),
            2 => _Response(200, ' ' * (257 * 1024)),
            _ => _Response(200, source),
          };
        });
        clients.add(client);
        return client;
      },
    );
  });
  test('加载失败有界返回，诊断不输出下载正文或原始异常', () async {
    var calls = 0;
    await HttpOverrides.runZoned(
      () async {
        await expectLater(
          HongguoVerificationSdk.download(),
          throwsA(
            isA<HongguoAccountFailure>().having(
              (v) => v.code,
              'code',
              'VERIFICATION_SDK_UNAVAILABLE',
            ),
          ),
        );
        expect(calls, 3);
        final logs = SourceDiagnostics.shared.entries
            .map((v) => v.toReportBlock())
            .join();
        expect(logs, isNot(contains('synthetic-private-body')));
        expect(logs, isNot(contains('synthetic-private-error')));
      },
      createHttpClient: (_) => _Client((_) {
        calls++;
        if (calls == 1) throw TimeoutException('synthetic-private-error');
        return _Response(200, 'synthetic-private-body');
      }),
    );
  });
  test('并发验证页面共享一次加载，公开组件仅缓存在内存', () async {
    var calls = 0;
    await HttpOverrides.runZoned(
      () async {
        expect(
          await Future.wait([
            HongguoVerificationSdk.load(),
            HongguoVerificationSdk.load(),
          ]),
          [source, source],
        );
        expect(await HongguoVerificationSdk.load(), source);
        expect(calls, 1);
      },
      createHttpClient: (_) => _Client((_) {
        calls++;
        return _Response(200, source);
      }),
    );
  });
}
