import 'hongguo_social_models.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../js/catpaw_js_runtime.dart';
import '../diagnostics/source_diagnostics.dart';
import 'hongguo_account_session.dart';
import 'account_transfer_payload.dart';
import 'hongguo_verification.dart';
import '../../models/catalog/models.dart';

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
  bool finalCheckDone = false;
  bool get confirmed => _cookies.hasSession;
}

class HongguoPhoneLogin {
  HongguoPhoneLogin(this.country, this.number, this._revision);
  final String country, number;
  final int _revision;
  final _cookies = HongguoAccountCookies();
  bool cancelled = false;
  bool sent = false;
  bool sendRequested = false;
  String? _fingerprint;
  DateTime retryAt = DateTime(2000);
  @override
  String toString() => 'HongguoPhoneLogin([redacted])';
}

class VerifiedAccountTransfer {
  VerifiedAccountTransfer(this.candidate, this.profile, this.revision);
  final AccountTransferPayload candidate;
  final Map<String, dynamic> profile;
  final int revision;
  @override
  String toString() => 'VerifiedAccountTransfer([redacted])';
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
    }().whenComplete(() => _initializing = null);
  }

  void _check(int revision) {
    if (_disposed || revision != session.revision) {
      throw const HongguoAccountFailure('账号操作已取消', 'CANCELLED');
    }
  }

  Future<({String body, Uri? redirect})> _request(
    Map<String, dynamic> command,
    HongguoAccountCookies? cookies,
    int revision, {
    String? diagnosticAction,
  }) async {
    _check(revision);
    final elapsed = Stopwatch()..start();
    final uri = Uri.parse(command['url'] as String);
    final web =
        uri.scheme == 'https' &&
        uri.host == 'hongguoduanju.com' &&
        !uri.hasPort;
    if (!web && !HongguoAccountSession.businessUrl(uri)) {
      throw const HongguoAccountFailure('账号地址未通过校验');
    }
    _http ??= HttpClient()..connectionTimeout = const Duration(seconds: 12);
    final method = command['method']?.toString() ?? 'GET';
    if (!{'GET', 'POST'}.contains(method)) {
      throw const HongguoAccountFailure('账号请求方式无效');
    }
    final request = await _http!
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 15));
    try {
      _check(revision);
    } catch (_) {
      request.abort();
      rethrow;
    }
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
    final csrf = web ? cookies?.csrfFor(uri) ?? '' : '';
    if (csrf.isNotEmpty) {
      request.headers.set('x-tt-passport-csrf-token', csrf);
    }
    if (method == 'POST') {
      final body = command['body'];
      if (body is! String || utf8.encode(body).length > 16 * 1024) {
        request.abort();
        throw const HongguoAccountFailure('账号请求格式无效');
      }
      request.write(body);
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
      _recordCreatorResponse(
        diagnosticAction,
        uri,
        method,
        response,
        '',
        elapsed,
      );
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
    final body = utf8.decode(bytes);
    _recordCreatorResponse(
      diagnosticAction,
      uri,
      method,
      response,
      body,
      elapsed,
    );
    return (body: body, redirect: null);
  }

  void _recordCreatorResponse(
    String? action,
    Uri uri,
    String method,
    HttpClientResponse response,
    String body,
    Stopwatch elapsed,
  ) {
    if (action != 'creatorFollow' ||
        uri.path != '/novel/commentapi/comment/do_action/v1/') {
      return;
    }
    Object? parsed;
    try {
      parsed = jsonDecode(body);
    } catch (_) {}
    final rawCode = parsed is Map ? parsed['code']?.toString() ?? '' : '';
    final business = RegExp(r'^-?\d{1,9}$').hasMatch(rawCode) ? rawCode : '';
    final risk = response.statusCode == 200 && business == '103012';
    String header(String name) {
      try {
        return response.headers.value(name) ?? '';
      } catch (_) {
        return '';
      }
    }

    final logId = header('x-tt-logid');
    final gatewayLogin = header('x-tt-agw-login');
    SourceDiagnostics.shared.add(
      SourceDiagnosticEntry(
        at: DateTime.now(),
        context: '红果作者关注',
        stage: 'creatorFollow',
        host: uri.host,
        url: Uri(scheme: uri.scheme, host: uri.host, path: uri.path).toString(),
        method: method,
        status: response.statusCode,
        businessCode: business,
        errorCode: response.statusCode != 200
            ? 'HTTP_${response.statusCode}'
            : business.isEmpty
            ? 'INVALID_RESPONSE'
            : business != '0'
            ? 'BUSINESS_$business'
            : '',
        logId: RegExp(r'^[0-9A-Fa-f]{16,64}$').hasMatch(logId) ? logId : '',
        elapsedMs: elapsed.elapsedMilliseconds,
        errorCategory: risk ? 'upstream_security' : '',
        errorTitle: risk ? '红果安全校验未通过' : '',
        errorMessage: risk ? '官方评论接口返回 HitSharkRule，具体触发条件未提供' : '',
        sessionStatus:
            'session=${session.loggedIn} verified=${session.verified} boundDevice=${session.deviceSession != null}'
            '${{'0', '1'}.contains(gatewayLogin) ? ' gatewayLogin=$gatewayLogin' : ''}',
      ),
    );
  }

  Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> payload,
    HongguoAccountCookies? cookies,
    int revision,
  ) async {
    _stage = action;
    var phase = 'prepare';
    try {
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
      phase = 'request';
      final response = await _request(
        command,
        cookies,
        revision,
        diagnosticAction: action,
      );
      if (response.redirect != null) {
        throw const HongguoAccountFailure('账号接口发生意外跳转', 'UNEXPECTED_REDIRECT');
      }
      _check(revision);
      phase = 'parse';
      final result = engine.accountParse(action, response.body);
      if (result['verification'] != null) {
        throw HongguoVerificationChallenge.fromResult(result, cookies);
      }
      if (action != 'poll') _trace(action, cookies);
      return result;
    } on HongguoAccountFailure catch (failure) {
      if (failure.code != 'CANCELLED') {
        _trace(
          action,
          cookies,
          code: failure.code,
          businessCode: failure is HongguoVerificationChallenge
              ? failure.businessCode
              : '',
        );
      }
      rethrow;
    } on TimeoutException {
      _check(revision);
      _trace(action, cookies, code: 'TIMEOUT');
      throw const HongguoAccountFailure('账号请求超时，请稍后重试', 'TIMEOUT');
    } on HandshakeException {
      _check(revision);
      _trace(action, cookies, code: 'TLS_ERROR');
      throw const HongguoAccountFailure('账号安全连接失败，请检查网络后重试', 'TLS_ERROR');
    } on SocketException {
      _check(revision);
      _trace(action, cookies, code: 'NETWORK_ERROR');
      throw const HongguoAccountFailure('账号网络连接失败，请检查网络后重试', 'NETWORK_ERROR');
    } catch (_) {
      _check(revision);
      final code = phase == 'prepare'
          ? 'PREPARATION_FAILED'
          : phase == 'parse'
          ? 'INVALID_RESPONSE'
          : 'REQUEST_FAILED';
      _trace(action, cookies, code: code);
      throw HongguoAccountFailure(
        phase == 'prepare' ? '账号登录初始化失败，请更新应用或使用扫码登录' : '账号响应暂不可用，请稍后重试',
        code,
      );
    }
  }

  void _trace(
    String phase,
    HongguoAccountCookies? cookies, {
    String status = '',
    String code = '',
    String businessCode = '',
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
    final trace = '$phase $summary $code $businessCode';
    if (_lastTrace == trace) return;
    _lastTrace = trace;
    SourceDiagnostics.shared.add(
      SourceDiagnosticEntry(
        at: DateTime.now(),
        context: phase == 'creatorFollow' ? '红果作者关注' : '红果登录',
        stage: phase,
        errorCode: code,
        businessCode: businessCode,
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

  Future<bool> poll(HongguoQrLogin login, {bool finalCheck = false}) async {
    if (_polling || login.cancelled) return false;
    _check(login._revision);
    if (!login.confirmed && !login.expiresAt.isAfter(DateTime.now())) {
      if (!finalCheck || login.finalCheckDone) {
        throw const HongguoAccountFailure('二维码已过期，请刷新', 'QR_EXPIRED');
      }
      login.finalCheckDone = true;
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
        isCurrent: () => !_disposed && !login.cancelled,
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

  HongguoPhoneLogin phone(String country, String number) =>
      HongguoPhoneLogin(country, number, session.revision);
  void _checkPhone(HongguoPhoneLogin attempt) {
    _check(attempt._revision);
    if (attempt.cancelled) {
      throw const HongguoAccountFailure('登录操作已取消', 'CANCELLED');
    }
  }

  Future<void> _preparePhone(HongguoPhoneLogin attempt) async {
    _checkPhone(attempt);
    if (attempt._cookies.csrf.isEmpty) {
      await _call('qr', {}, attempt._cookies, attempt._revision);
    }
    _checkPhone(attempt);
  }

  Future<Map<String, dynamic>> _phoneCall(
    String action,
    HongguoPhoneLogin attempt,
    Map<String, dynamic> payload,
    HongguoVerificationResolver? verify,
  ) async {
    Map<String, dynamic> fields() => {
      ...payload,
      'fingerprint': ?attempt._fingerprint,
    };
    try {
      return await _call(action, fields(), attempt._cookies, attempt._revision);
    } on HongguoVerificationChallenge catch (challenge) {
      _checkPhone(attempt);
      if (verify == null) rethrow;
      final fp = await verify(challenge);
      _checkPhone(attempt);
      if (fp == null) {
        throw const HongguoAccountFailure('安全验证已取消，本次请求未重试', 'CANCELLED');
      }
      if (!HongguoVerificationChallenge.validFingerprint(fp)) {
        throw const HongguoAccountFailure('安全验证结果无效', 'VERIFICATION_INVALID');
      }
      _trace('$action 安全验证回调', attempt._cookies);
      attempt._fingerprint = fp;
      attempt._cookies.merge(Uri.parse('https://hongguoduanju.com/'), [
        's_v_web_id=$fp; Path=/; Secure',
      ]);
      try {
        return await _call(
          action,
          fields(),
          attempt._cookies,
          attempt._revision,
        );
      } on HongguoVerificationChallenge {
        throw const HongguoAccountFailure(
          '官方尚未确认安全验证，请重试或使用红果 App 扫码登录',
          'VERIFICATION_NOT_ACCEPTED',
        );
      }
    }
  }

  Future<int> sendPhoneCode(
    HongguoPhoneLogin attempt, {
    HongguoVerificationResolver? verify,
  }) async {
    _checkPhone(attempt);
    if (attempt.retryAt.isAfter(DateTime.now())) {
      throw const HongguoAccountFailure('请等待短信倒计时结束');
    }
    await _preparePhone(attempt);
    attempt.sendRequested = true;
    final data = await _phoneCall('phoneCode', attempt, {
      'country': attempt.country,
      'number': attempt.number,
    }, verify);
    _checkPhone(attempt);
    final seconds = (data['retryAfter'] as num).toInt();
    attempt.sent = true;
    attempt.retryAt = DateTime.now().add(Duration(seconds: seconds));
    return seconds;
  }

  Future<void> loginPhone(
    HongguoPhoneLogin attempt, {
    required String code,
    HongguoVerificationResolver? verify,
  }) async {
    _checkPhone(attempt);
    if (!RegExp(r'^\d{4,8}$').hasMatch(code)) {
      throw const HongguoAccountFailure('请输入正确的验证码');
    }
    if (!attempt.sent && !attempt.sendRequested) {
      throw const HongguoAccountFailure('请先获取验证码');
    }
    await _preparePhone(attempt);
    await _phoneCall('phoneSms', attempt, {
      'country': attempt.country,
      'number': attempt.number,
      'code': code,
    }, verify);
    _checkPhone(attempt);
    if (!attempt._cookies.hasSession) {
      throw const HongguoAccountFailure('官方尚未签发有效登录会话');
    }
    await _call('webInfo', {}, attempt._cookies, attempt._revision);
    final profile = await _call(
      'profile',
      {},
      attempt._cookies,
      attempt._revision,
    );
    _checkPhone(attempt);
    await session.accept(
      attempt._cookies,
      profile,
      expectedRevision: attempt._revision,
      device: _profileDevice,
      isCurrent: () => !_disposed && !attempt.cancelled,
    );
    attempt.cancelled = true;
  }

  Future<VerifiedAccountTransfer> prepareTransferred(
    AccountTransferPayload candidate, {
    required bool Function() isCurrent,
    int? expectedRevision,
  }) async {
    final revision = expectedRevision ?? session.revision;
    _check(revision);
    if (!isCurrent()) throw const HongguoAccountFailure('设备配对已取消', 'CANCELLED');
    await _call('webInfo', {}, candidate.cookies, revision);
    final profile = await _call(
      'profile',
      {'device': candidate.device},
      candidate.cookies,
      revision,
    );
    _check(revision);
    if (profile['id'] != candidate.id || !isCurrent()) {
      throw const HongguoAccountFailure('传入会话未通过当前账号校验');
    }
    return VerifiedAccountTransfer(candidate, profile, revision);
  }

  Future<void> commitTransferred(
    VerifiedAccountTransfer verified, {
    required bool Function() isCurrent,
  }) async {
    _check(verified.revision);
    if (!isCurrent() || verified.profile['id'] != verified.candidate.id) {
      throw const HongguoAccountFailure('设备配对已取消', 'CANCELLED');
    }
    await session.accept(
      verified.candidate.cookies,
      verified.profile,
      expectedRevision: verified.revision,
      device: verified.candidate.device,
      isCurrent: () => !_disposed && isCurrent(),
    );
  }

  Future<void> importTransferred(
    AccountTransferPayload candidate, {
    required bool Function() isCurrent,
    int? expectedRevision,
  }) async {
    final verified = await prepareTransferred(
      candidate,
      isCurrent: isCurrent,
      expectedRevision: expectedRevision,
    );
    await commitTransferred(verified, isCurrent: isCurrent);
  }

  Future<void> verify() async {
    if (!session.loggedIn) return;
    final revision = session.revision;
    final account = await _call('profile', {}, null, revision);
    session.confirm(account, revision);
  }

  String _pickNonEmptyText(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  int _pickPositiveInt(Iterable<Object?> values) {
    for (final value in values) {
      final parsed = intValue(value);
      if (parsed > 0) return parsed;
    }
    return 0;
  }

  void _indexDetailRow(
    Map<String, Map<String, dynamic>> details,
    Map<String, dynamic> incoming,
  ) {
    final keys = <String>{
      for (final key in ['id', 'book_id', 'series_id'])
        if ((incoming[key]?.toString().trim() ?? '').isNotEmpty)
          incoming[key].toString().trim(),
    };
    for (final key in keys) {
      final existing = details[key];
      if (existing == null) {
        details[key] = incoming;
      } else {
        details[key] = {
          ...existing,
          ...incoming,
          'title': _pickNonEmptyText([incoming['title'], existing['title']]),
          'cover': _pickNonEmptyText([incoming['cover'], existing['cover']]),
          'description': _pickNonEmptyText([
            incoming['description'],
            existing['description'],
          ]),
          'episodes': _pickPositiveInt([
            incoming['episodes'],
            existing['episodes'],
          ]),
        };
      }
    }
  }

  Map<String, dynamic>? _resolveDetailForRow(
    Map<String, Map<String, dynamic>> details,
    Map<String, dynamic> row,
  ) {
    for (final key in [row['id'], row['book_id'], row['series_id']]) {
      final id = key?.toString().trim() ?? '';
      if (id.isNotEmpty && details.containsKey(id)) {
        return details[id];
      }
    }
    return null;
  }

  bool _isFatalAccountFailure(HongguoAccountFailure failure, int revision) {
    return !session.loggedIn ||
        revision != session.revision ||
        failure.code == 'CANCELLED' ||
        failure.code == 'SESSION_INVALID' ||
        failure.code == 'ACCOUNT_CHALLENGE_REQUIRED' ||
        failure.code == 'ACCOUNT_SECONDARY_VERIFICATION_REQUIRED';
  }

  void _recordLibraryDiagnostic({
    required String stage,
    required int total,
    int resolved = 0,
    int fallbackCount = 0,
    String errorCode = '',
    String message = '',
  }) {
    SourceDiagnostics.shared.add(
      SourceDiagnosticEntry(
        at: DateTime.now(),
        context: '红果账号列表补全',
        stage: stage,
        errorCode: errorCode,
        errorTitle: errorCode.isNotEmpty ? '批量剧集资料未完整匹配' : '',
        errorMessage: message.isNotEmpty
            ? message
            : '总数=$total, 详情匹配=$resolved, 单条补全=$fallbackCount',
        sessionStatus: 'loggedIn=${session.loggedIn}',
      ),
    );
  }

  Future<List<WatchEntry>> library({required bool history}) async {
    if (!session.loggedIn) throw const HongguoAccountFailure('请先登录红果账号');
    final revision = session.revision;
    final response = await _call(
      history ? 'history' : 'favorites',
      history ? {} : {'userId': session.id},
      null,
      revision,
    );
    final rows = (response['items'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final details = <String, Map<String, dynamic>>{};
    var batchErrorCode = '';
    for (var offset = 0; offset < rows.length; offset += 50) {
      final chunkIds = rows
          .skip(offset)
          .take(50)
          .map((v) => v['id'].toString())
          .where((v) => v.isNotEmpty)
          .join(',');
      if (chunkIds.isEmpty) continue;
      try {
        final result = await _call(
          'libraryDetails',
          {'ids': chunkIds},
          null,
          revision,
        );
        for (final item in result['items'] as List) {
          _indexDetailRow(details, Map<String, dynamic>.from(item as Map));
        }
      } on HongguoAccountFailure catch (failure) {
        if (_isFatalAccountFailure(failure, revision)) rethrow;
        batchErrorCode = failure.code;
      } catch (_) {
        _check(revision);
        batchErrorCode = 'BATCH_DETAIL_FAILED';
      }
    }

    final missingIndices = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final detail = _resolveDetailForRow(details, row);
      final title = _pickNonEmptyText([detail?['title'], row['title']]);
      final cover = _pickNonEmptyText([detail?['cover'], row['cover']]);
      final episodes = _pickPositiveInt([
        detail?['episodes'],
        row['episodes'],
      ]);
      if (title.isEmpty || cover.isEmpty || episodes <= 0) {
        missingIndices.add(i);
      }
    }

    var fallbackSucceeded = 0;
    const maxFallbackItems = 24;
    const concurrency = 4;
    final fallbackTargets = missingIndices.take(maxFallbackItems).toList();
    for (var start = 0; start < fallbackTargets.length; start += concurrency) {
      final batch = fallbackTargets.skip(start).take(concurrency).toList();
      await Future.wait(
        batch.map((index) async {
          final row = rows[index];
          final candidates = <String>[
            for (final key in ['series_id', 'id', 'book_id'])
              if ((row[key]?.toString().trim() ?? '').isNotEmpty)
                row[key].toString().trim(),
          ];
          final seenCandidates = <String>{};
          for (final candidate in candidates) {
            if (!seenCandidates.add(candidate)) continue;
            try {
              final single = await _call(
                'libraryDetail',
                {'id': candidate},
                null,
                revision,
              );
              final items = single['items'] as List? ?? const [];
              if (items.isNotEmpty) {
                final rawDetail = Map<String, dynamic>.from(items.first as Map);
                rawDetail.putIfAbsent('id', () => row['id']);
                rawDetail.putIfAbsent('series_id', () => candidate);
                if ((row['book_id']?.toString() ?? '').isNotEmpty) {
                  rawDetail.putIfAbsent('book_id', () => row['book_id']);
                }
                _indexDetailRow(details, rawDetail);
                final title = _pickNonEmptyText([rawDetail['title']]);
                final cover = _pickNonEmptyText([rawDetail['cover']]);
                final episodes = _pickPositiveInt([rawDetail['episodes']]);
                if (title.isNotEmpty || cover.isNotEmpty || episodes > 0) {
                  fallbackSucceeded++;
                  break;
                }
              }
            } on HongguoAccountFailure catch (failure) {
              if (_isFatalAccountFailure(failure, revision)) rethrow;
            } catch (_) {
              _check(revision);
            }
          }
        }),
      );
    }

    _check(revision);
    var resolvedCount = 0;
    final entries = rows.map((row) {
      final detail = _resolveDetailForRow(details, row);
      final id = row['id'].toString();
      final title = _pickNonEmptyText([detail?['title'], row['title']]);
      final cover = _pickNonEmptyText([detail?['cover'], row['cover']]);
      final description = _pickNonEmptyText([
        detail?['description'],
        row['description'],
      ]);
      final episodes = _pickPositiveInt([detail?['episodes'], row['episodes']]);
      if (title.isNotEmpty) resolvedCount++;
      return WatchEntry(
        drama: Drama(
          id: 'hongguo:$id',
          source: 'hongguo',
          sourceId: id,
          title: title.isEmpty ? '剧集$id' : title,
          cover: cover,
          description: description,
          episodes: episodes,
        ),
        episode: intValue(row['episode']),
        position: (row['positionMs'] as num? ?? 0) / 1000,
        duration: (row['durationMs'] as num? ?? 0) / 1000,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          intValue(row['updatedAt']),
        ),
      );
    }).toList();

    if (rows.isNotEmpty &&
        (batchErrorCode.isNotEmpty || missingIndices.isNotEmpty)) {
      _recordLibraryDiagnostic(
        stage: history ? 'history' : 'favorites',
        total: rows.length,
        resolved: resolvedCount,
        fallbackCount: fallbackSucceeded,
        errorCode: batchErrorCode,
      );
    }
    return entries;
  }

  Future<void> setFollowing(Drama drama, bool follow) async {
    if (!session.loggedIn) throw const HongguoAccountFailure('请先登录红果账号');
    final revision = session.revision;
    await _call(
      'favoriteUpdate',
      {'id': drama.cleanSourceId, 'follow': follow ? '1' : '0'},
      null,
      revision,
    );
    final result = await _call(
      'favorites',
      {'userId': session.id},
      null,
      revision,
    );
    final found = (result['items'] as List).any(
      (row) => (row as Map)['id'].toString() == drama.cleanSourceId,
    );
    if (found != follow) {
      throw const HongguoAccountFailure(
        '官方追剧状态尚未确认，请刷新后重试',
        'WRITE_NOT_CONFIRMED',
      );
    }
  }

  Future<WatchEntry?> progress(Drama drama) async {
    if (!session.loggedIn) throw const HongguoAccountFailure('请先登录红果账号');
    final revision = session.revision;
    Map<String, dynamic> result;
    try {
      result = await _call(
        'progressGet',
        {'id': drama.cleanSourceId},
        null,
        revision,
      );
    } on HongguoAccountFailure catch (error) {
      if (error.code != 'BUSINESS_101112') rethrow;
      result = await _call('history', {}, null, revision);
      if (!(result['items'] as List).any(
        (row) => (row as Map)['id'].toString() == drama.cleanSourceId,
      )) {
        rethrow;
      }
    }
    final rows = (result['items'] as List).cast<Map>();
    final row = rows
        .where((row) => row['id'].toString() == drama.cleanSourceId)
        .firstOrNull;
    if (row == null) return null;
    return WatchEntry(
      drama: drama,
      episode: intValue(row['episode']),
      position: (row['positionMs'] as num? ?? 0) / 1000,
      duration: (row['durationMs'] as num? ?? 0) / 1000,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        intValue(row['updatedAt']),
      ),
    );
  }

  Future<void> updateProgress(
    WatchEntry entry, {
    required String itemId,
  }) async {
    if (!session.loggedIn) throw const HongguoAccountFailure('请先登录红果账号');
    await _call(
      'progressUpdate',
      {
        'id': entry.drama.cleanSourceId,
        'itemId': itemId,
        'episode': entry.episode,
        'positionMs': (entry.position * 1000).round(),
        'durationMs': (entry.duration * 1000).round(),
        'episodes': entry.drama.episodes,
        'updatedAt': entry.updatedAt.millisecondsSinceEpoch,
      },
      null,
      session.revision,
    );
  }

  Future<List<HongguoCreator>> creators(Drama drama) async {
    if (!session.loggedIn) throw const HongguoAccountFailure('请先登录红果账号');
    final result = await _call(
      'creatorList',
      {'id': drama.cleanSourceId},
      null,
      session.revision,
    );
    return (result['creators'] as List)
        .map(
          (row) =>
              HongguoCreator.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<HongguoSocialSnapshot> social(Drama drama) async {
    if (!session.loggedIn) throw const HongguoAccountFailure('请先登录红果账号');
    final revision = session.revision;
    final result = await _call(
      'socialDetail',
      {'id': drama.cleanSourceId},
      null,
      revision,
    );
    if (result['id'] != drama.cleanSourceId) {
      throw const HongguoAccountFailure('互动状态的剧集编号不匹配');
    }
    final episodes = (result['episodes'] as List)
        .map(
          (row) => HongguoEpisodeLike.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
    List<HongguoCreator> people = [];
    String? error;
    try {
      people = await creators(drama);
    } on HongguoAccountFailure catch (issue) {
      error = issue.message;
    }
    _check(revision);
    return HongguoSocialSnapshot(episodes, people, creatorError: error);
  }

  Future<HongguoSocialSnapshot> setLiked(
    Drama drama,
    HongguoEpisodeLike episode,
    bool liked,
  ) async {
    if (!session.loggedIn) throw const HongguoAccountFailure('请先登录红果账号');
    final revision = session.revision;
    await _call(
      'likeUpdate',
      {'itemId': episode.id, 'like': liked ? '1' : '0'},
      null,
      revision,
    );
    _check(revision);
    final result = await social(drama);
    _check(revision);
    final readback = result.episode(episode.number);
    if (readback?.id != episode.id || readback?.liked != liked) {
      throw const HongguoAccountFailure(
        '官方点赞状态尚未确认，请刷新后重试',
        'WRITE_NOT_CONFIRMED',
      );
    }
    return result;
  }

  Future<List<HongguoCreator>> setCreatorFollowing(
    Drama drama,
    HongguoCreator creator,
    bool follow,
  ) async {
    if (!session.loggedIn) throw const HongguoAccountFailure('请先登录红果账号');
    if ((!creator.canFollow && follow) ||
        creator.following == null ||
        creator.id == session.id) {
      throw const HongguoAccountFailure('当前创作者暂不可关注');
    }
    final revision = session.revision;
    await _call(
      'creatorFollow',
      {
        'userId': creator.id,
        'relativeType': creator.relativeType,
        'follow': follow ? '1' : '0',
      },
      null,
      revision,
    );
    _check(revision);
    final rows = await creators(drama);
    _check(revision);
    final row = rows
        .where(
          (item) =>
              item.id == creator.id &&
              item.relativeType == creator.relativeType,
        )
        .firstOrNull;
    if (row?.following != follow) {
      throw const HongguoAccountFailure(
        '官方关注状态尚未确认，请刷新后重试',
        'WRITE_NOT_CONFIRMED',
      );
    }
    return rows;
  }

  void dispose() {
    _disposed = true;
    _http?.close(force: true);
    _runtime?.dispose();
  }
}
