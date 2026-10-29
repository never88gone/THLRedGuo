import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'hongguo_guest_session.dart';

import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';

class CatPawHomeResult {
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> filters;
  const CatPawHomeResult({required this.classes, required this.filters});
}

class CatPawCategoryResult {
  final int page;
  final int pageCount;
  final int limit;
  final int total;
  final List<Map<String, dynamic>> list;
  final bool hasMore;
  final String updatedText;

  const CatPawCategoryResult({
    required this.page,
    this.pageCount = 1,
    this.limit = 20,
    this.total = 0,
    required this.list,
    required this.hasMore,
    this.updatedText = '',
  });
}

typedef CatPawCatalogResult = CatPawCategoryResult;

class CatPawDetailResult {
  final Map<String, dynamic> vod;
  const CatPawDetailResult({required this.vod});
}

class CatPawPlayResult {
  final String url;
  final Map<String, String> header;
  final int parse;
  final int quality;
  final List<int> qualities;
  final String decryptionKey;
  final int mediaBytes;
  final int expiresAt;
  final String danmakuId;
  final String errorCode;
  const CatPawPlayResult({
    required this.url,
    required this.header,
    this.parse = 0,
    this.quality = 0,
    this.qualities = const [],
    this.decryptionKey = '',
    this.mediaBytes = 0,
    this.expiresAt = 0,
    this.danmakuId = '',
    this.errorCode = '',
  });
}

class CatPawSourceFailure implements Exception {
  const CatPawSourceFailure(this.message, {required this.code});
  final String message;
  final String code;
  factory CatPawSourceFailure.playback(String code) {
    final normalized = RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(code)
        ? code
        : 'NO_STREAM';
    final message = switch (normalized) {
      'cancelled' => '播放请求已取消',
      'MISSING_EPISODE' => '官方接口暂未返回本集编号',
      'BUSINESS_REJECTED' => '官方接口暂未允许读取本集',
      'SECURITY_BLOCKED' => '本集片源地址未通过校验',
      'MISSING_MODEL' => '官方接口暂未返回本集片源',
      'MEDIA_REJECTED' => '本集媒体地址暂不可用，请重试',
      'MEDIA_URL_EXPIRED' => '本集媒体地址已经过期，请重新获取',
      'MEDIA_HTTP_403' => '本集媒体节点拒绝了当前地址，请重新获取播放地址',
      'HTTP_403' => '官方播放接口拒绝当前请求，请导出诊断报告',
      'HTTP_429' => '官方播放接口请求过于频繁，请稍后再试',
      'INVALID_RESPONSE' => '官方接口返回的播放数据无效',
      'EMPTY_RESPONSE' => '官方播放接口连接成功，但没有返回播放数据',
      'RESPONSE_NOT_UTF8' => '官方播放接口返回了无法解码的数据',
      'GUEST_REGISTRATION_FAILED' => '官方访客会话初始化失败，请重试',
      _ => '站源暂未返回本集可播放地址，请重试',
    };
    return CatPawSourceFailure(message, code: normalized);
  }
  @override
  String toString() => message;
}

class CatPawSearchResult {
  final List<Map<String, dynamic>> list;
  final int page;
  final int pageCount;
  final bool hasMore;
  const CatPawSearchResult({
    required this.list,
    this.page = 1,
    this.pageCount = 1,
    this.hasMore = false,
  });
}

class CatPawJsRuntime {
  static Future<void> preloadDeviceSession() =>
      HongguoGuestSession.shared.preload();
  static String? get cachedDeviceSession => HongguoGuestSession.shared.value;
  static void resetDeviceSessionForTesting([String? session]) =>
      HongguoGuestSession.shared.resetForTesting(session);

  late final JavascriptRuntime _rt;
  final http.Client _httpClient;
  final bool _isOwnedClient;
  final SourceDiagnostics diagnostics;
  final String diagnosticContext;
  final bool persistentDeviceSession;
  SourceDiagnosticEntry? _lastSearchTrace;
  String? _injectedDeviceSession;
  DateTime? _injectedDeviceCreatedAt;
  bool _officialSource = false;
  int _successfulPlaybackResolves = 0;
  DateTime? _lastSuccessfulPlayback;
  int _evaluationSequence = 0;
  List<SourceDiagnosticEntry> _modelResponses = [];
  final HongguoGuestSession guestSessions;
  bool _ready = false;
  bool _isDisposed = false;
  final Set<Completer<void>> _requestAborts = {};
  int _activeRequests = 0;
  int _activeEvals = 0;
  int _cancellation = 0;
  Completer<void> _cancelSignal = Completer<void>();
  Completer<void>? _drainCompleter;
  Completer<void>? _evalDrainCompleter;

  CatPawJsRuntime([
    http.Client? client,
    SourceDiagnostics? recorder,
    String diagnosticContext = '日常使用',
    bool persistentDeviceSession = true,
  ]) : this.configured(
         client: client,
         recorder: recorder,
         diagnosticContext: diagnosticContext,
         persistentDeviceSession: persistentDeviceSession,
       );

  CatPawJsRuntime.configured({
    http.Client? client,
    SourceDiagnostics? recorder,
    this.diagnosticContext = '日常使用',
    this.persistentDeviceSession = true,
    HongguoGuestSession? guestSessions,
  }) : _httpClient = client ?? http.Client(),
       _isOwnedClient = client == null,
       diagnostics = recorder ?? SourceDiagnostics.shared,
       guestSessions = guestSessions ?? HongguoGuestSession.shared;

  bool get isReady => _ready;
  bool get isDisposed => _isDisposed;
  bool get hasPendingWork => _activeRequests > 0 || _activeEvals > 0;

  Future<void> init(String script) async {
    if (_isDisposed) throw StateError('CatPawJsRuntime 已被释放');
    if (persistentDeviceSession) await guestSessions.preload();
    _rt = getJavascriptRuntime(xhr: false);
    _injectGlobals();
    final result = _rt.evaluate(script);
    if (result.isError) {
      throw Exception('JS 脚本加载失败: ${result.rawResult}');
    }
    _officialSource =
        _rt
            .evaluate(
              'typeof spider !== "undefined" && spider.meta ? String(spider.meta.id) : ""',
            )
            .stringResult ==
        'hongguo';
    _ready = true;
  }

  void dispose() {
    if (_isDisposed) return;
    cancelPending();
    _isDisposed = true;
    _ready = false;

    if (_activeRequests == 0 && _activeEvals == 0) {
      _cleanup();
    } else {
      final futures = <Future<void>>[];
      if (_activeRequests > 0) {
        _drainCompleter ??= Completer<void>();
        futures.add(_drainCompleter!.future);
      }
      if (_activeEvals > 0) {
        _evalDrainCompleter ??= Completer<void>();
        futures.add(_evalDrainCompleter!.future);
      }
      Future.wait(futures).whenComplete(() {
        _cleanup();
      });
    }
  }

  void cancelPending() {
    if (_isDisposed || !_ready) return;
    _cancellation++;
    _cancelSignal.complete();
    _cancelSignal = Completer<void>();
    _rt.evaluate(r'''
globalThis.__hongguoCancelled = true;
Object.keys(globalThis.__fetchWaiters || {}).forEach(function(id) { __rejectFetch(id, 'CANCELLED'); });
globalThis.__fetchPendingQueue = [];
''');
    _rt.executePendingJob();
    for (final abort in _requestAborts.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
  }

  void _cleanup() {
    try {
      _rt.dispose();
    } catch (_) {}
    if (_isOwnedClient) {
      _httpClient.close();
    }
  }

  void _injectGlobals() {
    final random = Random.secure();
    final entropy = List.generate(
      64,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _rt.evaluate('globalThis.__hongguoEntropy = ${jsonEncode(entropy)};');
    _rt.evaluate(r'''
var JSON = JSON || {};
if (!JSON.stringify) JSON.stringify = function(o) { return "{}"; };
if (!JSON.parse) JSON.parse = function(s) { return {}; };
(function() {
  var nativeParse = JSON.parse;
  JSON.parse = function(text, reviver) {
    if (typeof text === 'string' && /\d{15,}/.test(text)) {
      var output = '';
      var copied = 0;
      var quoted = false;
      var escaped = false;
      var numberCharacters = '0123456789.eE+-';
      for (var index = 0; index < text.length; index++) {
        var character = text[index];
        if (quoted) {
          if (escaped) escaped = false;
          else if (character === '\\') escaped = true;
          else if (character === '"') quoted = false;
          continue;
        }
        if (character === '"') {
          quoted = true;
          continue;
        }
        if (character !== '-' && (character < '0' || character > '9')) continue;
        var start = index;
        while (index < text.length && numberCharacters.indexOf(text[index]) >= 0) index++;
        var token = text.slice(start, index);
        if (/^-?[1-9]\d{14,}$/.test(token)) {
          output += text.slice(copied, start) + '"' + token + '"';
          copied = index;
        }
        index--;
      }
      if (copied > 0) text = output + text.slice(copied);
    }
    return nativeParse(text, reviver);
  };
})();
// 强制无条件覆盖 console，杜绝宿主注入有缺陷的 C 原生 sendMessage('ConsoleLog', ...) 回调
globalThis.console = {
  log: function() {},
  warn: function() {},
  error: function() {},
  info: function() {}
};
''');

    _rt.evaluate(_evalAsyncShim);
    _rt.evaluate(_htmlShim);
    _rt.evaluate(_fetchShim);

    _syncDeviceSession();
    _rt.evaluate(r'''
globalThis.__pendingSavedDevice = null;
globalThis.__native_save_device = function(json) {
  if (json && typeof json === 'string') {
    globalThis.__pendingSavedDevice = json;
  }
};
''');
  }

  Future<Map<String, dynamic>> _executeFetch(
    Map<String, dynamic> params,
  ) async {
    if (_isDisposed) {
      return {'status': 0, 'headers': <String, String>{}, 'body': ''};
    }
    _activeRequests++;
    String url = '';
    final clock = Stopwatch()..start();
    var timedOut = false;
    try {
      url = params['url']?.toString() ?? '';
      final method = (params['method']?.toString() ?? 'GET').toUpperCase();
      final rawHeaders = params['headers'];
      final headers = <String, String>{};
      if (rawHeaders is Map) {
        rawHeaders.forEach((k, v) {
          if (k != null && v != null) headers[k.toString()] = v.toString();
        });
      }
      final body = params['body']?.toString();

      final uri = Uri.parse(url);
      final officialMetadata =
          uri.scheme == 'https' &&
          (uri.host == 'reading.snssdk.com' ||
              uri.host.endsWith('.fqnovel.com')) &&
          {
            '/novel/player/video_detail/v1/',
            '/reading/bookapi/search/tab/v',
            '/reading/bookapi/bookmall/tab/v',
            '/reading/bookapi/bookmall/cell/change/v',
          }.contains(uri.path);
      final responseLimit = (officialMetadata ? 12 : 2) * 1024 * 1024;
      final abort = Completer<void>();
      _requestAborts.add(abort);
      final timeoutMs = ((params['timeoutMs'] as num?)?.toInt() ?? 20000).clamp(
        1,
        30000,
      );
      final timer = Timer(Duration(milliseconds: timeoutMs), () {
        timedOut = true;
        if (!abort.isCompleted) abort.complete();
      });
      late http.Response resp;
      try {
        final request =
            http.AbortableRequest(method, uri, abortTrigger: abort.future)
              ..headers.addAll(headers)
              ..followRedirects = params['redirect'] != 'manual';
        if (body != null && method != 'HEAD' && method != 'GET') {
          request.body = body;
        }
        final response = await _httpClient
            .send(request)
            .timeout(Duration(milliseconds: timeoutMs));
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          Duration(milliseconds: timeoutMs),
        )) {
          if (bytes.length + chunk.length > responseLimit) {
            throw const FormatException('接口响应超过限制');
          }
          bytes.add(chunk);
        }
        resp = http.Response.bytes(
          bytes.takeBytes(),
          response.statusCode,
          headers: response.headers,
        );
      } finally {
        timer.cancel();
        _requestAborts.remove(abort);
        if (!abort.isCompleted) abort.complete();
      }

      if (_isDisposed) {
        return {'status': 0, 'headers': <String, String>{}, 'body': ''};
      }
      final entry = diagnostics.record(
        url: url,
        context: diagnosticContext,
        elapsedMs: clock.elapsedMilliseconds,
        status: resp.statusCode,
        body: resp.body,
        headers: resp.headers,
        method: method,
        sessionStatus: _guestStatus,
      );
      if (entry?.stage == '搜索') _lastSearchTrace = entry;
      if (entry?.stage == '播放解析' &&
          params['evaluation'] == _evaluationSequence) {
        _modelResponses.add(entry!);
      }
      return {
        'status': resp.statusCode,
        'headers': resp.headers,
        'body': resp.body,
      };
    } catch (e) {
      final entry = diagnostics.record(
        url: url,
        context: diagnosticContext,
        elapsedMs: clock.elapsedMilliseconds,
        errorCode: SourceDiagnostics.networkCode(e, timedOut: timedOut),
        error: e,
        timedOut: timedOut,
        method: (params['method']?.toString() ?? 'GET').toUpperCase(),
      );
      if (entry?.stage == '搜索') _lastSearchTrace = entry;
      // ignore: avoid_print
      print(
        '【FETCH ERROR】host=${Uri.tryParse(url)?.host}, type=${e.runtimeType}',
      );
      if (_isDisposed) {
        return {'status': 0, 'headers': <String, String>{}, 'body': ''};
      }
      return {
        'status': 0,
        'headers': <String, String>{},
        'body': '',
        'error': SourceDiagnostics.networkCode(e, timedOut: timedOut),
        'errorDetail': SourceDiagnostics.analyzeError(
          e,
          url: url,
          timedOut: timedOut,
        ).message,
        'category': switch (SourceDiagnostics.networkCode(
          e,
          timedOut: timedOut,
        )) {
          'DNS' => 'dns_error',
          'TIMEOUT' => 'network_timeout',
          'CONNECTION' => 'conn_refused',
          'TLS' => 'tls_error',
          'CANCELLED' => 'cancelled',
          _ => 'unknown',
        },
      };
    } finally {
      _activeRequests--;
      if (_isDisposed &&
          _activeRequests == 0 &&
          _drainCompleter != null &&
          !_drainCompleter!.isCompleted) {
        _drainCompleter!.complete();
      }
    }
  }

  Future<Map<String, dynamic>> getMeta() async {
    _assertReady();
    final res = await _evalAsync(
      'typeof spider !== "undefined" && spider.meta ? spider.meta : (typeof meta !== "undefined" ? meta : {})',
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {};
  }

  Future<CatPawHomeResult> home({bool filter = false}) async {
    _assertReady();
    final res = await _evalAsync(
      'typeof spider !== "undefined" && typeof spider.home === "function" ? spider.home($filter) : { class: [], filters: {} }',
      timeout: const Duration(seconds: 40),
      operation: '详情解析',
    );
    final map = (res is Map) ? res : {};
    final classes = _toListOfMaps(map['class'] ?? map['classes'] ?? []);
    final filters = _parseFilters(map['filters'] ?? map['filter'] ?? []);
    return CatPawHomeResult(classes: classes, filters: filters);
  }

  Future<CatPawCategoryResult> category(
    String tid,
    int page, {
    bool filter = false,
    Map<String, dynamic>? extend,
  }) async {
    _assertReady();
    final extendJson = jsonEncode(extend ?? {});
    final res = await _evalAsync(
      'typeof spider !== "undefined" && typeof spider.category === "function" ? spider.category(${jsonEncode(tid)}, $page, $filter, $extendJson) : { list: [], page: $page, pagecount: 1 }',
      timeout: const Duration(seconds: 40),
    );
    final map = (res is Map) ? res : {};
    final list = _toListOfMaps(map['list'] ?? []);
    final pg = (map['page'] as num?)?.toInt() ?? page;
    final pageCount =
        (map['pagecount'] as num?)?.toInt() ??
        (map['pageCount'] as num?)?.toInt() ??
        1;
    final limit = (map['limit'] as num?)?.toInt() ?? 20;
    final total = (map['total'] as num?)?.toInt() ?? 0;
    return CatPawCategoryResult(
      page: pg,
      pageCount: pageCount,
      limit: limit,
      total: total,
      list: list,
      hasMore: pg < pageCount,
    );
  }

  Future<CatPawDetailResult> detail(String id) async {
    _assertReady();
    final res = await _evalAsync(
      'typeof spider !== "undefined" && typeof spider.detail === "function" ? spider.detail(${jsonEncode(id)}) : { vod_id: ${jsonEncode(id)} }',
      timeout: const Duration(seconds: 40),
    );
    final map = (res is Map) ? res : {};
    dynamic vod = map['vod'];
    if (vod == null &&
        map['list'] is List &&
        (map['list'] as List).isNotEmpty) {
      vod = (map['list'] as List).first;
    }
    vod ??= map;
    return CatPawDetailResult(
      vod: Map<String, dynamic>.from(vod is Map ? vod : {'vod_id': id}),
    );
  }

  Future<Map<String, dynamic>> _discovery(
    String method,
    List<Object> arguments,
  ) async {
    _assertReady();
    final result = await _evalAsync(
      'typeof spider.$method === "function" ? spider.$method.apply(spider, ${jsonEncode(arguments)}) : Promise.reject(new Error("当前数据源暂不支持此功能"))',
      timeout: const Duration(seconds: 60),
    );
    if (result is! Map) throw const FormatException('官方列表数据无效');
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> seriesSeasons(String id) async {
    final result = await _discovery('seriesSeasons', [id]);
    return _toListOfMaps(result['list']);
  }

  Future<CatPawCategoryResult> feed(int page, String session) async {
    final result = await _discovery('feed', [page, session]);
    return CatPawCategoryResult(
      list: _toListOfMaps(result['list']),
      page: page,
      hasMore: result['hasMore'] == true,
    );
  }

  Future<List<String>> suggestions(String query) async {
    final result = await _discovery('suggestions', [query]);
    return (result['items'] as List? ?? const [])
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toSet()
        .take(10)
        .toList();
  }

  Future<List<Map<String, dynamic>>> rankingBoards() async {
    final result = await _discovery('rankingBoards', []);
    return _toListOfMaps(result['items']);
  }

  Future<CatPawCategoryResult> discoveryPage(
    String method,
    String key,
    int page,
  ) async {
    if (!{'rankings', 'recommendations'}.contains(method)) {
      throw ArgumentError.value(method);
    }
    final result = await _discovery(method, [key, page]);
    final returnedPage = (result['page'] as num?)?.toInt() ?? page;
    final pageCount = (result['pagecount'] as num?)?.toInt() ?? returnedPage;
    return CatPawCategoryResult(
      list: _toListOfMaps(result['list']),
      page: returnedPage,
      pageCount: pageCount,
      hasMore: result['hasMore'] as bool? ?? returnedPage < pageCount,
      updatedText: result['updatedText']?.toString() ?? '',
    );
  }

  Future<CatPawPlayResult> play(
    String flag,
    String id, {
    List<dynamic>? flags,
  }) async {
    _assertReady();
    final flagsJson = jsonEncode(flags ?? []);
    final dynamic res;
    try {
      res = await _evalAsync(
        'typeof spider !== "undefined" && typeof spider.play === "function" ? spider.play(${jsonEncode(flag)}, ${jsonEncode(id)}, $flagsJson) : { parse: 0, url: "" }',
        timeout: const Duration(seconds: 60),
        operation: '播放取流',
        recoverGuest: true,
      );
    } on CatPawSourceFailure {
      rethrow;
    }
    final map = (res is Map) ? res : {};
    final url = map['url']?.toString() ?? '';
    final parse = (map['parse'] as num?)?.toInt() ?? 0;
    final contentKey =
        map['decryptionKey']?.toString().trim().toLowerCase() ?? '';
    if (contentKey.isNotEmpty &&
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(contentKey)) {
      throw const FormatException('站源内容密钥无效');
    }
    if (url.isNotEmpty) {
      _successfulPlaybackResolves++;
      _lastSuccessfulPlayback = guestSessions.now();
    }
    final header = <String, String>{};
    final rawHeader = map['header'] ?? map['headers'];
    if (rawHeader is Map) {
      rawHeader.forEach((k, v) {
        if (k != null && v != null) header[k.toString()] = v.toString();
      });
    }
    return CatPawPlayResult(
      url: url,
      header: header,
      parse: parse,
      decryptionKey: contentKey,
      mediaBytes: (map['mediaBytes'] as num?)?.toInt() ?? 0,
      expiresAt: (map['expiresAt'] as num?)?.toInt() ?? 0,
      danmakuId: map['danmakuId']?.toString() ?? '',
      errorCode: map['error']?.toString() ?? '',
      quality: (map['quality'] as num?)?.toInt() ?? 0,
      qualities:
          (map['qualities'] is List ? map['qualities'] as List : const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .where((value) => value > 0)
              .toList(),
    );
  }

  Future<Map<String, dynamic>> danmaku(
    String id,
    int startMs,
    int durationMs,
  ) async {
    _assertReady();
    final result = await _evalAsync(
      'typeof spider.danmaku === "function" ? spider.danmaku(${jsonEncode(id)}, $startMs, $durationMs) : Promise.reject(new Error("本集暂不支持弹幕"))',
      timeout: const Duration(seconds: 20),
    );
    if (result is! Map) throw const FormatException('弹幕响应无效');
    return Map<String, dynamic>.from(result);
  }

  Future<CatPawSearchResult> search(
    String keyword, {
    bool quick = false,
    int page = 1,
  }) async {
    _assertReady();
    final dynamic res;
    _lastSearchTrace = null;
    try {
      res = await _evalAsync(
        'typeof spider !== "undefined" && typeof spider.search === "function" ? spider.search(${jsonEncode(keyword)}, $quick, $page) : []',
        timeout: const Duration(seconds: 60),
        operation: '搜索调用',
      );
    } catch (error) {
      final code = error is CatPawSourceFailure
          ? SourceDiagnostics.safeCode(error.code)
          : 'SEARCH_EXECUTION';
      final analysis = SourceDiagnostics.analyzeError(error);
      diagnostics.add(
        SourceDiagnosticEntry(
          at: DateTime.now().toUtc(),
          context: diagnosticContext,
          stage: '搜索执行',
          url: _lastSearchTrace?.url ?? '',
          host: _lastSearchTrace?.host ?? '',
          status: _lastSearchTrace?.status ?? 0,
          logId: _lastSearchTrace?.logId ?? '',
          businessCode: _lastSearchTrace?.businessCode ?? '',
          searchTabsSummary: _lastSearchTrace?.searchTabsSummary ?? '',
          sessionStatus: _lastSearchTrace?.sessionStatus ?? '',
          errorCode: code.isEmpty ? 'SEARCH_EXECUTION' : code,
          errorCategory: analysis.category,
          errorTitle: analysis.title,
          errorMessage: SourceDiagnostics.redact(analysis.message),
          advice: analysis.advice,
        ),
      );
      rethrow;
    }
    List<Map<String, dynamic>> list = [];
    if (res is List) {
      list = _toListOfMaps(res);
    } else if (res is Map) {
      list = _toListOfMaps(res['list'] ?? []);
    }
    final resultPage = res is Map
        ? (res['page'] as num?)?.toInt() ?? page
        : page;
    final pageCount = res is Map
        ? (res['pagecount'] as num?)?.toInt() ??
              (res['pageCount'] as num?)?.toInt() ??
              resultPage
        : resultPage;
    return CatPawSearchResult(
      list: list,
      page: resultPage,
      pageCount: pageCount,
      hasMore: resultPage < pageCount,
    );
  }

  Future<void> _evalQueue = Future.value();

  Future<dynamic> _evalAsync(
    String jsCode, {
    Duration timeout = const Duration(seconds: 30),
    String operation = '',
    bool recoverGuest = false,
  }) async {
    _assertReady();
    final cancellation = _cancellation;
    final cancelled = _cancelSignal.future;
    final stopwatch = Stopwatch()..start();
    var queueMs = 0;
    Object? failure;
    Completer<void>? initializationOwner;
    final prevQueue = _evalQueue;
    final queueCompleter = Completer<void>();
    _evalQueue = queueCompleter.future;
    _activeEvals++;
    try {
      try {
        await prevQueue;
      } catch (_) {}
      queueMs = stopwatch.elapsedMilliseconds;
      if (cancellation != _cancellation || _isDisposed) {
        throw CatPawSourceFailure.playback('cancelled');
      }
      while (_officialSource &&
          persistentDeviceSession &&
          guestSessions.initialization != null) {
        await Future.any([guestSessions.initialization!, cancelled]);
        if (cancellation != _cancellation || _isDisposed) {
          throw CatPawSourceFailure.playback('cancelled');
        }
      }
      if (cancellation != _cancellation || _isDisposed) {
        throw CatPawSourceFailure.playback('cancelled');
      }
      if (_officialSource && persistentDeviceSession) {
        if (await guestSessions.refresh()) {
          diagnostics.add(
            SourceDiagnosticEntry(
              at: DateTime.now().toUtc(),
              context: diagnosticContext,
              stage: '游客会话同步',
              sessionStatus: '请求前载入其他运行环境更新的游客会话，保留搜索和详情缓存',
            ),
          );
        }
        if (cancellation != _cancellation || _isDisposed) {
          throw CatPawSourceFailure.playback('cancelled');
        }
      }
      while (_officialSource &&
          persistentDeviceSession &&
          guestSessions.value == null &&
          guestSessions.initialization != null) {
        await Future.any([guestSessions.initialization!, cancelled]);
        if (cancellation != _cancellation || _isDisposed) {
          throw CatPawSourceFailure.playback('cancelled');
        }
      }
      if (_officialSource &&
          persistentDeviceSession &&
          guestSessions.value == null) {
        initializationOwner = guestSessions.beginInitialization();
      }
      final data = await _runEval(jsCode, timeout, stopwatch, cancellation);
      if (!recoverGuest || !_officialSource || !persistentDeviceSession) {
        return data;
      }
      if (!_emptyModelFailure(data)) return data;
      final session = _injectedDeviceSession;
      await guestSessions.refresh();
      if (cancellation != _cancellation || _isDisposed) {
        throw CatPawSourceFailure.playback('cancelled');
      }
      if (guestSessions.value == null || guestSessions.value == session) {
        return data;
      }
      diagnostics.add(
        SourceDiagnosticEntry(
          at: DateTime.now().toUtc(),
          context: diagnosticContext,
          stage: '游客会话同步',
          sessionStatus: '载入其他请求已更新的游客会话，保留本地资料和搜索游标',
        ),
      );
      return await _runEval(jsCode, timeout, stopwatch, cancellation);
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      if (initializationOwner != null) {
        guestSessions.completeInitialization(initializationOwner);
      }
      if (operation.isNotEmpty) {
        diagnostics.add(
          SourceDiagnosticEntry(
            at: DateTime.now().toUtc(),
            context: diagnosticContext,
            stage: '$operation（排队 ${queueMs}ms）',
            sessionStatus: operation == '播放取流' ? _guestStatus : '',
            elapsedMs: stopwatch.elapsedMilliseconds,
            errorCode: failure is CatPawSourceFailure
                ? failure.code
                : failure == null
                ? ''
                : SourceDiagnostics.networkCode(failure),
          ),
        );
      }
      queueCompleter.complete();
      _activeEvals--;
      if (_isDisposed &&
          _activeEvals == 0 &&
          _evalDrainCompleter != null &&
          !_evalDrainCompleter!.isCompleted) {
        _evalDrainCompleter!.complete();
      }
    }
  }

  Future<dynamic> _runEval(
    String jsCode,
    Duration timeout,
    Stopwatch stopwatch,
    int cancellation,
  ) async {
    _assertReady();
    if (cancellation != _cancellation) {
      throw CatPawSourceFailure.playback('cancelled');
    }
    final evaluation = ++_evaluationSequence;
    _modelResponses = [];
    _syncDeviceSession();
    _rt.evaluate('globalThis.__hongguoCancelled = false;');
    final evalStart = _rt.evaluate(
      '__startEval(function() { return ($jsCode); })',
    );
    if (evalStart.isError) {
      throw Exception('JS 表达式启动失败: ${evalStart.rawResult}');
    }

    final taskId = int.tryParse(evalStart.stringResult) ?? 0;
    if (taskId == 0) {
      throw Exception('JS 任务初始化失败: ${evalStart.rawResult}');
    }

    dynamic rawResult;

    while (true) {
      if (cancellation != _cancellation) {
        throw CatPawSourceFailure.playback('cancelled');
      }
      if (stopwatch.elapsed > timeout) {
        cancelPending();
        throw TimeoutException('数据请求超时，请检查网络或稍后重试', timeout);
      }

      // 1. 处理待发起的网络请求
      final drainResult = _rt.evaluate('__drainFetches()');
      final drainStr = drainResult.stringResult;
      if (drainStr.isNotEmpty && drainStr != '[]' && drainStr != 'null') {
        try {
          final dynamic list = jsonDecode(drainStr);
          if (list is List) {
            for (final item in list) {
              if (item is Map) {
                final req = Map<String, dynamic>.from(item)
                  ..['evaluation'] = evaluation;
                final id = req['id'];
                unawaited(
                  _executeFetch(req)
                      .then((resp) {
                        if (!_isDisposed && cancellation == _cancellation) {
                          final safeJson = jsonEncode(resp)
                              .replaceAll('\u2028', '\\u2028')
                              .replaceAll('\u2029', '\\u2029');
                          _rt.evaluate('__resolveFetch($id, $safeJson);');
                        }
                      })
                      .catchError((err) {
                        if (!_isDisposed && cancellation == _cancellation) {
                          _rt.evaluate(
                            '__rejectFetch($id, ${jsonEncode(err.toString())});',
                          );
                        }
                      }),
                );
              }
            }
          }
        } catch (_) {}
      }

      // 2. 检查主异步任务是否完成
      final pollResult = _rt.evaluate('__pollEval($taskId)');
      final pollStr = pollResult.stringResult;
      if (pollStr.isNotEmpty && pollStr != 'null') {
        try {
          final dynamic pollJson = jsonDecode(pollStr);
          if (pollJson is Map && pollJson['done'] == true) {
            rawResult = pollJson['result'];
            break;
          }
        } catch (_) {}
      }

      _syncSavedDevice();
      _rt.executePendingJob();
      await Future.delayed(const Duration(milliseconds: 10));
    }

    _syncSavedDevice();

    final raw = rawResult?.toString() ?? '';
    if (raw.isEmpty || raw == 'null' || raw == 'undefined') {
      return null;
    }
    dynamic data;
    try {
      data = jsonDecode(raw);
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
    } catch (e) {
      data = raw;
    }

    if (data is Map && data['__error'] == true) {
      final code = data['code']?.toString() ?? '';
      throw CatPawSourceFailure(
        '站源执行失败：${data['message']}',
        code: RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(code)
            ? code
            : 'JS_EXECUTION',
      );
    }
    return data;
  }

  String get _guestStatus {
    if (!persistentDeviceSession) return '独立游客会话';
    final now = guestSessions.now();
    final created = _injectedDeviceCreatedAt;
    final age = created == null
        ? '未记录'
        : '${max(0, now.difference(created).inSeconds)}秒';
    final last = _lastSuccessfulPlayback;
    final success = last == null
        ? '本次尚未成功'
        : '${max(0, now.difference(last).inSeconds)}秒前';
    return '游客会话创建距今：$age；本环境成功取流：$_successfulPlaybackResolves次；最近成功：$success';
  }

  bool _emptyModelFailure(dynamic data) =>
      data is Map &&
      data['error'] == 'EMPTY_RESPONSE' &&
      _modelResponses.length == 4 &&
      _modelResponses.every(
        (entry) => entry.status == 200 && entry.errorCode == 'EMPTY_RESPONSE',
      );

  void _syncDeviceSession() {
    if (!persistentDeviceSession) return;
    final session = guestSessions.value;
    if (_injectedDeviceSession == session) {
      _injectedDeviceCreatedAt = guestSessions.createdAt;
      return;
    }
    _successfulPlaybackResolves = 0;
    _lastSuccessfulPlayback = null;
    _rt.evaluate(
      'if (typeof HongguoApp !== "undefined" && typeof HongguoApp.resetGuestSession === "function") HongguoApp.resetGuestSession();',
    );
    if (session == null) {
      _rt.evaluate('delete globalThis.__hongguoCachedDevice;');
    } else {
      _rt.evaluate(
        'globalThis.__hongguoCachedDevice = JSON.parse(${jsonEncode(session)});',
      );
    }
    _injectedDeviceSession = session;
    _injectedDeviceCreatedAt = guestSessions.createdAt;
  }

  String? snapshotDetail(String id) {
    if (!_ready || _isDisposed || !RegExp(r'^\d{10,30}$').hasMatch(id)) {
      return null;
    }
    final result = _rt.evaluate(
      'JSON.stringify(globalThis.__hongguoDetailCache && globalThis.__hongguoDetailCache.get(${jsonEncode(id)}) || globalThis.__hongguoFeedDetails && globalThis.__hongguoFeedDetails.get(${jsonEncode(id)}) || null)',
    );
    final value = result.stringResult;
    return result.isError || value.isEmpty || value == 'null' ? null : value;
  }

  void restoreDetail(String id, String snapshot) {
    if (!_ready || _isDisposed || !RegExp(r'^\d{10,30}$').hasMatch(id)) return;
    _rt.evaluate('''
(function() {
  const entry = JSON.parse(${jsonEncode(snapshot)});
  if (!entry || !entry.data || !Number.isFinite(entry.updated) || Date.now() - entry.updated > 300000) return;
  const cache = globalThis.__hongguoDetailCache || (globalThis.__hongguoDetailCache = new Map());
  if (!(cache instanceof Map)) return;
  const previous = cache.get(${jsonEncode(id)});
  if (previous && previous.updated >= entry.updated) return;
  cache.set(${jsonEncode(id)}, entry);
  while (cache.size > 16) cache.delete(cache.keys().next().value);
})();
''');
  }

  void _syncSavedDevice() {
    try {
      final check = _rt.evaluate('globalThis.__pendingSavedDevice');
      final val = check.stringResult;
      if (val.isNotEmpty && val != 'null' && val != 'undefined') {
        _rt.evaluate('globalThis.__pendingSavedDevice = null;');
        if (!persistentDeviceSession || !HongguoGuestSession.valid(val)) return;
        guestSessions.accept(val);
        if (_injectedDeviceSession != val) {
          _successfulPlaybackResolves = 0;
          _lastSuccessfulPlayback = null;
        }
        _injectedDeviceSession = val;
        _injectedDeviceCreatedAt = guestSessions.createdAt;
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _toListOfMaps(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> _parseFilters(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else if (raw is Map) {
      return raw.entries
          .map(
            (e) => <String, dynamic>{'key': e.key.toString(), 'value': e.value},
          )
          .toList();
    }
    return [];
  }

  void _assertReady() {
    if (_isDisposed) throw StateError('CatPawJsRuntime 已经被销毁');
    if (!_ready) throw StateError('CatPawJsRuntime 尚未初始化，请先调用 init()');
  }

  static const _evalAsyncShim = r'''
globalThis.__evalTaskCounter = 0;
globalThis.__evalTasks = {};

globalThis.__startEval = function(fn) {
  var id = ++globalThis.__evalTaskCounter;
  globalThis.__evalTasks[id] = { done: false, result: null };
  (async function() {
    try {
      var res = await fn();
      globalThis.__evalTasks[id].result = JSON.stringify(res);
      globalThis.__evalTasks[id].done = true;
    } catch (e) {
      globalThis.__evalTasks[id].result = JSON.stringify({
        __error: true,
        code: e && e.code ? String(e.code) : "JS_EXECUTION",
        message: e ? (e.message || String(e)) : "Unknown JS error"
      });
      globalThis.__evalTasks[id].done = true;
    }
  })();
  return id;
};

globalThis.__pollEval = function(id) {
  var task = globalThis.__evalTasks[id];
  if (!task) return '{"done":true,"result":null}';
  if (task.done) {
    var res = task.result;
    delete globalThis.__evalTasks[id];
    return JSON.stringify({ done: true, result: res });
  }
  return '{"done":false}';
};
''';

  static const _fetchShim = r'''
globalThis.__fetchReqId = 0;
globalThis.__fetchPendingQueue = [];
globalThis.__fetchWaiters = {};

globalThis.fetch = function(url, opts) {
  opts = opts || {};
  var method = (opts.method || 'GET').toUpperCase();
  var headers = opts.headers || {};
  var body = opts.body || '';
  if (typeof body === 'object') {
    try { body = JSON.stringify(body); } catch (_) {}
  }
  var id = ++globalThis.__fetchReqId;
  return new Promise(function(resolve, reject) {
    globalThis.__fetchWaiters[id] = { resolve: resolve, reject: reject };
    globalThis.__fetchPendingQueue.push({
      id: id,
      url: String(url),
      method: method,
      headers: headers,
      body: String(body),
      timeoutMs: opts.timeoutMs || 12000,
      redirect: opts.redirect || 'follow'
    });
  });
};

globalThis.__drainFetches = function() {
  if (globalThis.__fetchPendingQueue.length === 0) return '[]';
  var list = globalThis.__fetchPendingQueue;
  globalThis.__fetchPendingQueue = [];
  return JSON.stringify(list);
};

globalThis.__resolveFetch = function(id, respObj) {
  var waiter = globalThis.__fetchWaiters[id];
  if (waiter) {
    delete globalThis.__fetchWaiters[id];
    var status = (respObj && typeof respObj.status === 'number') ? respObj.status : 200;
    var respBody = (respObj && respObj.body != null) ? String(respObj.body) : '';
    var respHeaders = (respObj && respObj.headers) ? respObj.headers : {};
    if (status === 0 && respObj && respObj.error) {
      var failure = new Error(respObj.errorDetail || '网络请求失败');
      failure.code = respObj.error;
      failure.category = respObj.category || 'unknown';
      waiter.reject(failure);
      return;
    }
    waiter.resolve({
      status: status,
      ok: status >= 200 && status < 300,
      headers: respHeaders,
      body: respBody,
      text: async function() { return respBody; },
      json: async function() {
        try {
          if (typeof respBody === 'object' && respBody !== null) return respBody;
          return JSON.parse(respBody);
        } catch (e) {
          return {};
        }
      }
    });
  }
};

globalThis.__rejectFetch = function(id, errMsg) {
  var waiter = globalThis.__fetchWaiters[id];
  if (waiter) {
    delete globalThis.__fetchWaiters[id];
    var failure = new Error(errMsg || 'Network request failed');
    failure.code = errMsg === 'CANCELLED' ? 'CANCELLED' : 'HTTP_0';
    waiter.reject(failure);
  }
};
''';

  static const _htmlShim = r'''
var html = (function() {
  var voidTags = {
    area: true, base: true, br: true, col: true, embed: true,
    hr: true, img: true, input: true, link: true, meta: true,
    param: true, source: true, track: true, wbr: true
  };

  function parseAttrs(attrStr) {
    var attrs = {};
    if (!attrStr) return attrs;
    var re = /([a-zA-Z0-9_\-:]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
    var match;
    while ((match = re.exec(attrStr)) !== null) {
      var key = match[1].toLowerCase();
      var val = match[2] !== undefined ? match[2] : (match[3] !== undefined ? match[3] : (match[4] !== undefined ? match[4] : ""));
      attrs[key] = val;
    }
    return attrs;
  }

  function Node(tag, attrs) {
    this.tag = (tag || "").toLowerCase();
    this.attrs = attrs || {};
    this.children = [];
    this.parent = null;
    this.texts = [];
  }

  Node.prototype.text = function() {
    var parts = [];
    function collect(n) {
      for (var i = 0; i < n.texts.length; i++) {
        if (n.texts[i]) parts.push(n.texts[i]);
      }
      for (var j = 0; j < n.children.length; j++) {
        collect(n.children[j]);
      }
    }
    collect(this);
    return parts.join(" ").replace(/\s+/g, " ").trim();
  };

  Node.prototype.attr = function(name) {
    if (!name) return "";
    return this.attrs[name.toLowerCase()] || "";
  };

  function matchSingle(node, sel) {
    if (!sel || !node.tag) return false;
    sel = sel.trim();
    if (sel === "*") return true;
    if (sel.indexOf("#") === 0) {
      var id = sel.substring(1);
      return (node.attrs["id"] || "") === id;
    }
    if (sel.indexOf(".") === 0) {
      var cls = sel.substring(1);
      var nodeCls = node.attrs["class"] || "";
      var classes = nodeCls.split(/\s+/);
      return classes.indexOf(cls) !== -1;
    }
    if (sel.indexOf(".") > 0) {
      var parts = sel.split(".");
      var tag = parts[0].toLowerCase();
      var c = parts[1];
      if (node.tag !== tag) return false;
      var nCls = node.attrs["class"] || "";
      return nCls.split(/\s+/).indexOf(c) !== -1;
    }
    if (sel.indexOf("#") > 0) {
      var p = sel.split("#");
      var t = p[0].toLowerCase();
      var i = p[1];
      return node.tag === t && (node.attrs["id"] || "") === i;
    }
    return node.tag === sel.toLowerCase();
  }

  function NodeList(nodes) {
    this._nodes = nodes || [];
    this.length = this._nodes.length;
    for (var i = 0; i < this._nodes.length; i++) {
      this[i] = this._wrapNode(this._nodes[i]);
    }
  }

  NodeList.prototype._wrapNode = function(node) {
    return {
      tag: node.tag,
      attrs: node.attrs,
      text: function() { return node.text(); },
      attr: function(name) { return node.attr(name); },
      find: function(sel) { return findInNodes([node], sel); },
      eq: function(idx) { return (idx === 0) ? this : NodeList.empty().eq(0); },
      first: function() { return this; },
      length: 1
    };
  };

  NodeList.empty = function() {
    return new NodeList([]);
  };

  NodeList.prototype.eq = function(idx) {
    if (idx < 0 || idx >= this._nodes.length) {
      return {
        text: function() { return ""; },
        attr: function() { return ""; },
        find: function() { return NodeList.empty(); },
        eq: function() { return NodeList.empty().eq(0); },
        first: function() { return NodeList.empty().eq(0); },
        length: 0
      };
    }
    return this._wrapNode(this._nodes[idx]);
  };

  NodeList.prototype.first = function() {
    return this.eq(0);
  };

  NodeList.prototype.text = function() {
    var arr = [];
    for (var i = 0; i < this._nodes.length; i++) {
      var t = this._nodes[i].text();
      if (t) arr.push(t);
    }
    return arr.join(" ").replace(/\s+/g, " ").trim();
  };

  NodeList.prototype.attr = function(name) {
    if (this._nodes.length === 0) return "";
    return this._nodes[0].attr(name);
  };

  NodeList.prototype.find = function(sel) {
    return findInNodes(this._nodes, sel);
  };

  function findInNodes(roots, selector) {
    if (!selector) return NodeList.empty();
    var parts = selector.trim().split(/\s+/);
    var currentNodes = roots.slice();

    for (var p = 0; p < parts.length; p++) {
      var subSel = parts[p];
      var nextLevel = [];
      for (var n = 0; n < currentNodes.length; n++) {
        var startNode = currentNodes[n];
        var matched = [];
        function walk(node, isRoot) {
          if (!isRoot && matchSingle(node, subSel)) {
            matched.push(node);
          }
          for (var c = 0; c < node.children.length; c++) {
            walk(node.children[c], false);
          }
        }
        walk(startNode, true);
        for (var m = 0; m < matched.length; m++) {
          if (nextLevel.indexOf(matched[m]) === -1) {
            nextLevel.push(matched[m]);
          }
        }
      }
      currentNodes = nextLevel;
    }
    return new NodeList(currentNodes);
  }

  function parseHtml(htmlStr) {
    if (!htmlStr) return new NodeList([]);
    var root = new Node("root", {});
    var current = root;

    var clean = String(htmlStr)
      .replace(/<!--[\s\S]*?-->/g, "")
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/<style[\s\S]*?<\/style>/gi, "");

    var tagRegex = /<(\/)?([a-zA-Z0-9_\-]+)([^>]*)>|([^<]+)/g;
    var match;

    while ((match = tagRegex.exec(clean)) !== null) {
      var isClose = !!match[1];
      var tagName = match[2];
      var rawAttrs = match[3];
      var textContent = match[4];

      if (textContent) {
        var t = textContent.trim();
        if (t) current.texts.push(t);
      } else if (tagName) {
        var lowerTag = tagName.toLowerCase();
        if (isClose) {
          var temp = current;
          while (temp && temp !== root && temp.tag !== lowerTag) {
            temp = temp.parent;
          }
          if (temp && temp !== root) {
            current = temp.parent || root;
          }
        } else {
          var attrs = parseAttrs(rawAttrs);
          var newNode = new Node(lowerTag, attrs);
          newNode.parent = current;
          current.children.push(newNode);

          var isSelfClosing = voidTags[lowerTag] || (rawAttrs && rawAttrs.trim().slice(-1) === "/");
          if (!isSelfClosing) {
            current = newNode;
          }
        }
      }
    }

    return {
      find: function(selector) {
        return findInNodes([root], selector);
      },
      text: function() {
        return root.text();
      }
    };
  }

  return {
    parse: parseHtml
  };
})();
''';
}

class CatPawRuntimePool {
  final http.Client _httpClient;
  final bool _ownsClient;
  final Map<String, CatPawJsRuntime> _pool = {};
  final Map<String, String> _scripts = {};
  final Map<String, Future<CatPawJsRuntime>> _pending = {};
  final Map<String, int> _generations = {};
  bool _isDisposed = false;

  CatPawRuntimePool([http.Client? httpClient])
    : _httpClient = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  bool get isDisposed => _isDisposed;

  Future<CatPawJsRuntime> get(
    String sourceId,
    String script, {
    String scope = 'catalog',
  }) async {
    if (_isDisposed) throw StateError('CatPawRuntimePool 已经销毁');
    final key = '$sourceId\u0000$scope';
    if (_scripts[key] == script) {
      final pending = _pending[key];
      if (pending != null) return pending;
      final runtime = _pool[key];
      if (runtime != null) return runtime;
    }
    _removeKey(key);
    final generation = _generations[key]!;
    _scripts[key] = script;
    final runtime = CatPawJsRuntime(_httpClient);
    final future = () async {
      try {
        await runtime.init(script);
        if (_isDisposed || _generations[key] != generation) {
          throw CatPawSourceFailure.playback('cancelled');
        }
        _pool[key] = runtime;
        return runtime;
      } catch (_) {
        runtime.dispose();
        rethrow;
      }
    }();
    _pending[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_pending[key], future)) _pending.remove(key);
    }
  }

  void _removeKey(String key) {
    _generations[key] = (_generations[key] ?? 0) + 1;
    _pending.remove(key);
    _scripts.remove(key);
    _pool.remove(key)?.dispose();
  }

  void cancelPending({String? sourceId, String? scope}) {
    for (final key in _scripts.keys.toList()) {
      final parts = key.split('\u0000');
      if (sourceId != null && parts.first != sourceId) continue;
      if (scope != null && parts.last != scope) continue;
      if (_pending.containsKey(key) || _pool[key]?.hasPendingWork == true) {
        _removeKey(key);
      }
    }
  }

  void shareDetail(String sourceId, String id, CatPawJsRuntime target) {
    if (sourceId != 'hongguo') return;
    for (final entry in _pool.entries) {
      if (!entry.key.startsWith('$sourceId\u0000') ||
          identical(entry.value, target)) {
        continue;
      }
      final snapshot = entry.value.snapshotDetail(id);
      if (snapshot != null) target.restoreDetail(id, snapshot);
    }
  }

  void remove(String sourceId) {
    for (final key
        in _scripts.keys
            .where((key) => key.startsWith('$sourceId\u0000'))
            .toList()) {
      _removeKey(key);
    }
  }

  void clear() {
    for (final key in _scripts.keys.toList()) {
      _removeKey(key);
    }
  }

  void disposeAll() {
    if (_isDisposed) return;
    _isDisposed = true;
    clear();
    if (_ownsClient) _httpClient.close();
  }
}
