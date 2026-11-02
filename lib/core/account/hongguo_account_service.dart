import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../js/catpaw_js_runtime.dart';
import '../diagnostics/source_diagnostics.dart';
import 'hongguo_account_session.dart';

class HongguoQrLogin {
  HongguoQrLogin(
    this.url,
    this.expiresAt,
    this._token,
    this._cookies,
    this._revision,
  );
  final String url;
  final DateTime expiresAt;
  final String _token;
  final HongguoAccountCookies _cookies;
  final int _revision;
  bool cancelled = false;
  bool get confirmed => _cookies.hasSession;
}

class HongguoAccountService {
  HongguoAccountService({HongguoAccountSession? session})
    : session = session ?? HongguoAccountSession.shared;
  final HongguoAccountSession session;
  CatPawJsRuntime? _runtime;
  Future<CatPawJsRuntime>? _initializing;
  HttpClient? _http;
  bool _disposed = false;
  bool _polling = false;
  String? _profileDevice;
  String _stage = 'idle';
  String _lastTrace = '';
  Future<CatPawJsRuntime> _engine() async {
    if (_disposed) throw const HongguoAccountFailure('账号操作已取消', 'CANCELLED');
    if (_runtime != null) return _runtime!;
    return _initializing ??= () async {
      final script = await rootBundle.loadString('assets/sources/hongguo.js');
      final runtime = CatPawJsRuntime();
      await runtime.init(script);
      if (_disposed) {
        runtime.dispose();
        throw const HongguoAccountFailure('账号操作已取消', 'CANCELLED');
      }
      return _runtime = runtime;
    }();
  }

  void _check(int revision) {
    if (_disposed || revision != session.revision) {
      throw const HongguoAccountFailure('账号操作已取消', 'CANCELLED');
    }
  }

  Future<({String body, Uri? redirect})> _request(
    Map<String, dynamic> command,
    HongguoAccountCookies? cookies,
    int revision,
  ) async {
    _check(revision);
    final uri = Uri.parse(command['url'] as String);
    final web =
        uri.scheme == 'https' &&
        uri.host == 'hongguoduanju.com' &&
        !uri.hasPort;
    if (!web && !HongguoAccountSession.businessUrl(uri)) {
      throw const HongguoAccountFailure('账号地址未通过校验');
    }
    _http ??= HttpClient()..connectionTimeout = const Duration(seconds: 12);
    final request = await _http!
        .openUrl('GET', uri)
        .timeout(const Duration(seconds: 15));
    request.followRedirects = false;
    if (web) {
      request.headers.set('User-Agent', 'Mozilla/5.0 THLRedLook/1.0.0');
      request.headers.set('Referer', 'https://hongguoduanju.com/');
    }
    final headers = Map<String, dynamic>.from(command['headers'] as Map? ?? {});
    headers.forEach((k, v) => request.headers.set(k, v.toString()));
    final cookie = web
        ? cookies?.websiteHeader(uri) ?? ''
        : cookies?.businessHeader ?? session.headerFor(uri);
    if (cookie.isNotEmpty) request.headers.set('Cookie', cookie);
    if (web && (cookies?.csrf.isNotEmpty ?? false)) {
      request.headers.set('x-tt-passport-csrf-token', cookies!.csrf);
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    _check(revision);
    cookies?.merge(uri, response.headers[HttpHeaders.setCookieHeader] ?? []);
    if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (!web || location == null) {
        throw const HongguoAccountFailure('登录确认跳转无效');
      }
      return (body: '', redirect: uri.resolve(location));
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HongguoAccountFailure(
        '账号请求失败（HTTP ${response.statusCode}）',
        'HTTP_${response.statusCode}',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      _check(revision);
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const HongguoAccountFailure('账号响应过大');
      }
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) {
      throw const HongguoAccountFailure('账号接口返回空正文', 'EMPTY_RESPONSE');
    }
    return (body: utf8.decode(bytes), redirect: null);
  }

  Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> payload,
    HongguoAccountCookies? cookies,
    int revision,
  ) async {
    _stage = action;
    final engine = await _engine();
    _check(revision);
    final command = await engine.accountRequest(action, payload);
    if (action == 'profile') {
      final query = Uri.parse(command['url'] as String).queryParameters;
      _profileDevice = jsonEncode({
        for (final key in ['iid', 'device_id', 'cdid'])
          if (query[key] != null) key: query[key],
      });
    }
    final response = await _request(command, cookies, revision);
    if (response.redirect != null) {
      throw const HongguoAccountFailure('账号接口发生意外跳转');
    }
    _check(revision);
    try {
      final result = engine.accountParse(action, response.body);
      if (action != 'poll') _trace(action, cookies);
      return result;
    } on HongguoAccountFailure catch (failure) {
      _trace(action, cookies, code: failure.code);
      rethrow;
    }
  }

  void _trace(
    String phase,
    HongguoAccountCookies? cookies, {
    String status = '',
    String code = '',
  }) {
    final safeStatus =
        {
          '0',
          '1',
          '2',
          '3',
          '4',
          '5',
          'new',
          'scanned',
          'confirmed',
          'expired',
          'cancelled',
          '',
        }.contains(status)
        ? status
        : 'unknown';
    final summary =
        'status=$safeStatus session=${cookies?.hasSession ?? session.loggedIn}';
    final trace = '$phase $summary $code';
    if (_lastTrace == trace) return;
    _lastTrace = trace;
    SourceDiagnostics.shared.add(
      SourceDiagnosticEntry(
        at: DateTime.now(),
        context: '红果登录',
        stage: phase,
        errorCode: code,
        sessionStatus: summary,
      ),
    );
  }

  Future<HongguoQrLogin> begin() async {
    final revision = session.revision;
    final cookies = HongguoAccountCookies();
    final data = await _call('qr', {}, cookies, revision);
    final expiry = (data['expiresAt'] as num).toInt();
    final expiresAt = expiry > 1000000000
        ? DateTime.fromMillisecondsSinceEpoch(expiry * 1000)
        : DateTime.now().add(Duration(seconds: expiry.clamp(0, 600)));
    if (!expiresAt.isAfter(DateTime.now())) {
      throw const HongguoAccountFailure('二维码已过期，请刷新');
    }
    return HongguoQrLogin(
      data['qrUrl'] as String,
      expiresAt,
      data['token'] as String,
      cookies,
      revision,
    );
  }

  Future<bool> poll(HongguoQrLogin login) async {
    if (_polling || login.cancelled) return false;
    _check(login._revision);
    if (!login.confirmed && !login.expiresAt.isAfter(DateTime.now())) {
      throw const HongguoAccountFailure('二维码已过期，请刷新', 'QR_EXPIRED');
    }
    _polling = true;
    try {
      final data = login._cookies.hasSession
          ? <String, dynamic>{}
          : await _call(
              'poll',
              {'token': login._token},
              login._cookies,
              login._revision,
            );
      if (login.cancelled) return false;
      final status = data['status'];
      _trace('poll', login._cookies, status: status.toString());
      if (status == 'expired' || status == '5') {
        throw const HongguoAccountFailure('二维码已过期，请刷新', 'QR_EXPIRED');
      }
      if (status == 'cancelled') {
        throw const HongguoAccountFailure('手机已取消登录，请刷新二维码', 'CANCELLED');
      }
      var redirect = status == 'confirmed' || status == '3'
          ? data['redirect'] as String
          : '';
      if (redirect.isNotEmpty) _stage = 'redirect';
      for (var step = 0; redirect.isNotEmpty && step < 5; step++) {
        final uri = Uri.parse('https://hongguoduanju.com/').resolve(redirect);
        if (uri.scheme != 'https' ||
            uri.host != 'hongguoduanju.com' ||
            uri.hasPort) {
          throw const HongguoAccountFailure('登录确认地址未通过校验');
        }
        final response = await _request(
          {'url': uri.toString()},
          login._cookies,
          login._revision,
        );
        redirect = response.redirect?.toString() ?? '';
      }
      if (redirect.isNotEmpty) throw const HongguoAccountFailure('登录确认跳转次数过多');
      if (!login._cookies.hasSession) return false;
      await _call('webInfo', {}, login._cookies, login._revision);
      final profile = await _call(
        'profile',
        {},
        login._cookies,
        login._revision,
      );
      if (login.cancelled) return false;
      await session.accept(
        login._cookies,
        profile,
        expectedRevision: login._revision,
        device: _profileDevice,
      );
      login.cancelled = true;
      _trace('saved', login._cookies);
      return true;
    } on HongguoAccountFailure catch (failure) {
      _trace(_stage, login._cookies, code: failure.code);
      rethrow;
    } finally {
      _polling = false;
    }
  }

  Future<void> verify() async {
    if (!session.loggedIn) return;
    final revision = session.revision;
    final account = await _call('profile', {}, null, revision);
    session.confirm(account, revision);
  }

  void dispose() {
    _disposed = true;
    _http?.close(force: true);
    _runtime?.dispose();
  }
}
