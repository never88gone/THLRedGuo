import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'network_egress_lookup.dart';

/// 诊断分析结果对象，包含清晰分类、具体失败原因与针对性排查建议
class DiagnosticAnalysisResult {
  const DiagnosticAnalysisResult({
    required this.category,
    required this.title,
    required this.message,
    required this.advice,
    required this.code,
    this.businessCode = '',
  });

  final String category;
  final String title;
  final String message;
  final String advice;
  final String code;
  final String businessCode;
}

class SourceDiagnosticEntry {
  const SourceDiagnosticEntry({
    required this.at,
    required this.context,
    required this.stage,
    this.host = '',
    this.url = '',
    this.method = 'GET',
    this.logId = '',
    this.status = 0,
    this.businessCode = '',
    this.errorCode = '',
    this.elapsedMs = 0,
    this.count,
    this.errorCategory = '',
    this.errorTitle = '',
    this.errorMessage = '',
    this.advice = '',
    this.responseSnippet = '',
    this.searchTabsSummary = '',
    this.sessionStatus = '',
  });

  final DateTime at;
  final String context;
  final String stage;
  final String host;
  final String url;
  final String method;
  final String logId;
  final int status;
  final String businessCode;
  final String errorCode;
  final int elapsedMs;
  final int? count;
  final String errorCategory;
  final String errorTitle;
  final String errorMessage;
  final String advice;
  final String responseSnippet;
  final String searchTabsSummary;
  final String sessionStatus;

  bool get failed =>
      errorCode.isNotEmpty ||
      errorCategory.isNotEmpty ||
      (status > 0 && status != 200);

  String get displayTitle => errorTitle.isNotEmpty
      ? errorTitle
      : (errorCode.isNotEmpty ? errorCode : '正常');

  String get text => [
    '${at.toIso8601String()} [$context] $stage',
    if (host.isNotEmpty) host,
    if (status > 0) 'HTTP $status',
    if (businessCode.isNotEmpty) '业务码 $businessCode',
    if (errorTitle.isNotEmpty)
      '[$errorTitle]'
    else if (errorCode.isNotEmpty)
      errorCode,
    if (errorMessage.isNotEmpty) errorMessage,
    if (elapsedMs > 0) '${elapsedMs}ms',
    if (count != null) '$count 条结果',
  ].join(' · ');

  String toReportBlock() {
    final buffer = StringBuffer();
    buffer.writeln(
      '  ${failed ? '✗' : '✓'} [${at.toIso8601String()}] $stage · $context',
    );
    if (failed) buffer.writeln('    - 判定: $displayTitle · $errorCode');
    if (host.isNotEmpty) buffer.writeln('    - 目标主机: $host');
    if (url.isNotEmpty) {
      buffer.writeln(
        '    - 请求接口: $method ${SourceDiagnostics.desensitizeUrl(url)}',
      );
    }
    if (status > 0) buffer.writeln('    - HTTP 状态码: $status');
    if (businessCode.isNotEmpty) buffer.writeln('    - 接口业务码: $businessCode');
    if (logId.isNotEmpty) buffer.writeln('    - LogID: $logId');
    if (sessionStatus.isNotEmpty) buffer.writeln('    - 会话状态: $sessionStatus');
    if (searchTabsSummary.isNotEmpty) {
      buffer.writeln('    - 搜索分类: $searchTabsSummary');
    }
    if (errorMessage.isNotEmpty) buffer.writeln('    - 具体失败原因: $errorMessage');
    if (advice.isNotEmpty) buffer.writeln('    - 排查指引: $advice');
    if (elapsedMs > 0) buffer.writeln('    - 请求耗时: ${elapsedMs}ms');
    if (count != null) buffer.writeln('    - 数据条数: $count');
    if (responseSnippet.isNotEmpty) {
      buffer.writeln('    - 响应结构摘要: $responseSnippet');
    }
    return SourceDiagnostics.redact(buffer.toString().trimRight());
  }
}

class SourceDiagnostics extends ChangeNotifier {
  static final shared = SourceDiagnostics();
  SourceDiagnostics({this.networkLookup = const NetworkEgressLookup()});
  final NetworkEgressLookup networkLookup;
  NetworkEgressResult? networkEgress;
  Future<void>? _networkTask;

  Future<void> refreshNetworkEgress({bool force = false}) async {
    final pending = _networkTask;
    if (pending != null) return pending;
    final previous = networkEgress;
    if (!force &&
        previous != null &&
        DateTime.now().toUtc().difference(previous.at).inSeconds <
            (previous.ip.isEmpty ? 30 : 300)) {
      return;
    }
    final task = () async {
      networkEgress = await networkLookup.lookup();
      notifyListeners();
    }();
    _networkTask = task;
    try {
      await task;
    } finally {
      _networkTask = null;
    }
  }

  final List<SourceDiagnosticEntry> _entries = [];
  List<SourceDiagnosticEntry> get entries => List.unmodifiable(_entries);

  void add(SourceDiagnosticEntry entry) {
    _entries.add(entry);
    if (_entries.length > 60) _entries.removeAt(0);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  static String safeCode(Object? value) {
    final code = value?.toString() ?? '';
    return RegExp(r'^-?[A-Za-z0-9_.:-]{1,64}$').hasMatch(code) &&
            !RegExp(r'\d{10,}').hasMatch(code)
        ? code
        : '';
  }

  static String? stageFor(Uri uri) {
    if (uri.host == 'log.snssdk.com' &&
        uri.path == '/service/2/device_register/') {
      return '游客注册';
    }
    if (uri.host == 'reading.snssdk.com' &&
        uri.path == '/reading/bookapi/search/tab/v') {
      return '搜索';
    }
    if (uri.host == 'reading.snssdk.com') {
      final stage = switch (uri.path) {
        '/reading/bookapi/search/cue/v' => '猜你想搜',
        '/reading/bookapi/search/suggest/v' => '搜索联想',
        '/reading/bookapi/plan/v' => '榜单',
        '/reading/bookapi/bookmall/tab/v' => '找剧与推荐',
        '/reading/bookapi/bookmall/cell/change/v' => '列表分页',
        _ => null,
      };
      if (stage != null) return stage;
    }
    if (uri.host.endsWith('.fqnovel.com') || uri.host == 'reading.snssdk.com') {
      if (uri.path.contains('/video_detail/')) {
        return '详情';
      }
      if (uri.path.contains('/video_model/') ||
          uri.path.contains('/multi_video_model/')) {
        return '播放解析';
      }
      if (uri.path.startsWith('/novel/commentapi/comment/list/')) {
        return '弹幕';
      }
    }
    if (uri.host == 'hongguoduanju.com' ||
        uri.host.endsWith('.hongguoduanju.com')) {
      if (uri.path == '/detail' || uri.path.startsWith('/detail/')) {
        return '详情';
      }
      if (uri.path.startsWith('/player/')) {
        return '播放解析';
      }
      return '网页路由';
    }
    return null;
  }

  /// 深入分析异常对象，精准归类为具体的失败原因
  static DiagnosticAnalysisResult analyzeError(
    Object error, {
    String url = '',
    bool timedOut = false,
  }) {
    final host = Uri.tryParse(url)?.host ?? '';
    final target = host.isNotEmpty ? host : '目标服务器';

    if (timedOut || error is TimeoutException) {
      return DiagnosticAnalysisResult(
        category: 'TIMEOUT',
        title: '网络请求超时',
        message: '向 $target 发起的网络连接超时，未在指定时限内收到响应',
        advice: '网络延迟过高或目标服务器响应缓慢，建议切换网络环境后重新检测。',
        code: 'TIMEOUT',
      );
    }

    if (error is http.RequestAbortedException) {
      return const DiagnosticAnalysisResult(
        category: 'CANCELLED',
        title: '请求已主动取消',
        message: '操作已由用户或系统主动取消',
        advice: '如非手动取消，可重新发起检测。',
        code: 'CANCELLED',
      );
    }

    if (error is HandshakeException || error is TlsException) {
      return DiagnosticAnalysisResult(
        category: 'TLS',
        title: 'SSL/TLS 证书握手失败',
        message: '与 $target 建立 HTTPS 安全连接协商失败，证书校验不通过',
        advice: '请检查设备系统时间与时区是否准确，并检查是否开启了中间人抓包或自签名代理证书。',
        code: 'TLS',
      );
    }

    final raw = error.toString();
    final lower = raw.toLowerCase();

    // 0. 站源业务/分集提取异常
    if (error.runtimeType.toString() == 'CatPawSourceFailure') {
      final dynamic dyn = error;
      final c = (dyn.code as Object?)?.toString().trim() ?? '';
      final msg = (dyn.message as Object?)?.toString() ?? '';
      if ([
        'SEARCH_TAB_MISSING',
        'INVALID_SEARCH_CURSOR',
        'SEARCH_EMPTY',
        'INVALID_RESPONSE',
        'EMPTY_RESPONSE',
        'RESPONSE_NOT_UTF8',
      ].contains(c)) {
        return DiagnosticAnalysisResult(
          category: 'DATA_PARSE',
          title: c == 'SEARCH_TAB_MISSING' ? '官方未提供短剧分类' : '接口响应异常',
          message: msg,
          advice: adviceForCode(c),
          code: c,
        );
      }
      if (['DNS', 'TIMEOUT', 'CONNECTION', 'TLS', 'CANCELLED'].contains(c)) {
        return DiagnosticAnalysisResult(
          category: c,
          title: switch (c) {
            'DNS' => 'DNS 解析错误',
            'TIMEOUT' => '网络请求超时',
            'CONNECTION' => '网络连接不通',
            'TLS' => 'SSL/TLS 证书握手失败',
            _ => '请求已主动取消',
          },
          message: msg,
          advice: adviceForCode(c),
          code: c,
        );
      }
      if (c.startsWith('HTTP_')) {
        final status = int.tryParse(c.substring(5));
        if (status != null && status > 0) {
          return analyzeHttpResponse(status, '', url: url);
        }
      }
      if (c == 'MISSING_EPISODE') {
        return DiagnosticAnalysisResult(
          category: 'DATA_PARSE',
          title: '缺少分集播放列表',
          message: msg.isNotEmpty
              ? msg
              : '剧集详情返回的数据中缺少分集播放列表 (vod_play_url 为空)',
          advice: '选取的短剧在官方站源可能属于预告或已下架，请检查站源分集解析规则或更换剧目。',
          code: 'MISSING_EPISODE',
        );
      }
      if (c == 'NO_STREAM_URL') {
        return DiagnosticAnalysisResult(
          category: 'MEDIA_STREAM',
          title: '媒体流解析失败',
          message: msg.isNotEmpty ? msg : '未能成功解析出有效媒体流播放地址',
          advice: '站源未能提供有效的流媒体播放地址，请检查播放解析逻辑或目标分集状态。',
          code: 'NO_STREAM_URL',
        );
      }
      if (c == 'SEARCH_REJECTED') {
        return DiagnosticAnalysisResult(
          category: 'BUSINESS',
          title: '搜索请求被拒',
          message: msg.isNotEmpty ? msg : '官方搜索接口未返回有效结果',
          advice: '搜索请求被服务端拦截或暂无结果，请稍后重试。',
          code: 'SEARCH_REJECTED',
        );
      }
      if (c == 'DISCOVERY_REJECTED') {
        return DiagnosticAnalysisResult(
          category: 'BUSINESS',
          title: '官方发现接口受限',
          message: msg.isNotEmpty ? msg : '官方发现接口暂不可用',
          advice: '发现与推荐服务可能暂时受限，请稍后刷新重试。',
          code: 'DISCOVERY_REJECTED',
        );
      }
      if (c == 'JS_EXECUTION') {
        return DiagnosticAnalysisResult(
          category: 'JS',
          title: 'JS 脚本报错',
          message: msg.isNotEmpty ? msg : 'JS 脚本执行抛出异常',
          advice: '数据源脚本运行报错，请复制报告反馈。',
          code: 'JS_EXECUTION',
        );
      }
      if (c.isNotEmpty) {
        return DiagnosticAnalysisResult(
          category: 'BUSINESS',
          title: '站源业务异常 ($c)',
          message: msg.isNotEmpty ? msg : '站源执行失败: $c',
          advice: adviceForCode(c),
          code: c,
        );
      }
    }

    // 1. DNS 解析错误
    if (lower.contains('failed host lookup') ||
        lower.contains('name or service not known') ||
        lower.contains('nodename nor servname') ||
        lower.contains('could not resolve host') ||
        lower.contains('getaddrinfo') ||
        (lower.contains('socketexception') && lower.contains('host lookup'))) {
      return DiagnosticAnalysisResult(
        category: 'DNS',
        title: 'DNS 解析错误',
        message: '无法解析域名 [$target]，系统未能获取到其 IP 地址',
        advice:
            '域名无法被解析，通常为本地 DNS 故障、去广告规则（如 AdGuard/hosts）拦截或分流代理规则阻断，请尝试使用手机热点对照。',
        code: 'DNS',
      );
    }

    // 2. TLS/证书失败
    if (lower.contains('handshake') ||
        lower.contains('certificate') ||
        lower.contains('cert_authority_invalid')) {
      return DiagnosticAnalysisResult(
        category: 'TLS',
        title: 'SSL/TLS 证书握手失败',
        message: '与 $target 建立安全连接失败：${_sanitizeErrorMessage(raw)}',
        advice: '安全连接失败，请检查设备系统时间和网络证书或代理工具。',
        code: 'TLS',
      );
    }

    // 3. 网络不通 / 连接拒绝
    if (lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('no route to host') ||
        lower.contains('connection reset') ||
        lower.contains('software caused connection abort') ||
        lower.contains('network down') ||
        error is SocketException ||
        error is http.ClientException) {
      return DiagnosticAnalysisResult(
        category: 'CONNECTION',
        title: '网络连接不通',
        message: '连接 $target 失败：目标主机拒绝连接或网络不可达',
        advice: '无法与服务器建立 TCP 连接，请检查设备联网状态、网络防火墙或代理软件是否正常工作。',
        code: 'CONNECTION',
      );
    }

    // 4. JS 报错
    if (lower.contains('typeerror') ||
        lower.contains('referenceerror') ||
        lower.contains('syntaxerror') ||
        lower.contains('evalerror') ||
        lower.contains('js 脚本') ||
        lower.contains('js 表达式') ||
        lower.contains('站源执行失败') ||
        lower.contains('javascript')) {
      return DiagnosticAnalysisResult(
        category: 'JS',
        title: 'JS 脚本报错',
        message: 'JS 脚本执行抛出异常: ${_sanitizeErrorMessage(raw)}',
        advice: '数据源脚本运行报错，通常为脚本解析逻辑与当前数据不匹配或 JS 引擎兼容性问题，可复制报告反馈。',
        code: 'JS_EXECUTION',
      );
    }

    // 5. 格式错误
    if (error is FormatException) {
      return DiagnosticAnalysisResult(
        category: 'DATA_PARSE',
        title: '数据返回格式异常',
        message: '服务端响应内容格式不符合预期: ${_sanitizeErrorMessage(raw)}',
        advice: '接口返回的数据无法被正确解析，可能是接口变动或返回了反爬拦截页。',
        code: 'INVALID_RESPONSE',
      );
    }

    return DiagnosticAnalysisResult(
      category: 'NETWORK_ERROR',
      title: '未知网络异常',
      message: _sanitizeErrorMessage(raw),
      advice: '请结合失败阶段和错误详情反馈排查。',
      code: 'NETWORK_ERROR',
    );
  }

  /// 深入分析 HTTP 响应，提取状态码与业务码
  static DiagnosticAnalysisResult analyzeHttpResponse(
    int status,
    String body, {
    String url = '',
    String stage = '',
  }) {
    final host = Uri.tryParse(url)?.host ?? '';
    final target = host.isNotEmpty ? host : '服务器';

    if (status != 200 && status > 0) {
      final desc = switch (status) {
        403 => '访问被拒绝 (403 Forbidden)，可能触发了防爬规则或 IP 限制',
        404 => '接口不存在 (404 Not Found)',
        429 => '请求频次过高 (429 Too Many Requests)，被限流保护',
        500 => '源站内部错误 (500 Internal Server Error)',
        502 => '源站网关异常 (502 Bad Gateway)',
        503 => '源站服务暂不可用 (503 Service Unavailable)',
        504 => '源站网关超时 (504 Gateway Timeout)',
        _ => '服务器返回 HTTP $status 状态',
      };
      final advice = switch (status) {
        403 || 429 => '服务端拒绝了当前访问，请保留报告，稍后或更换网络出口 IP 重试。',
        500 || 502 || 503 || 504 => '源站服务器临时故障，请稍后重新测试。',
        _ => '接口返回异常 HTTP 状态码，请保留报告以供排查。',
      };
      return DiagnosticAnalysisResult(
        category: 'HTTP',
        title: 'HTTP 状态异常 (HTTP $status)',
        message: '$target 返回: $desc',
        advice: advice,
        code: 'HTTP_$status',
      );
    }

    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return DiagnosticAnalysisResult(
        category: 'DATA_PARSE',
        title: '接口响应为空',
        message: '$target 返回 HTTP 200，但响应内容为空 (0 字节)',
        advice: '目标端点返回了空响应，可能该接口已被服务商下线或需要特定请求签名。',
        code: 'EMPTY_RESPONSE',
      );
    }

    final isHtml =
        trimmed.startsWith('<!DOCTYPE') ||
        trimmed.startsWith('<!doctype') ||
        trimmed.startsWith('<html') ||
        (host.contains('hongguoduanju.com') &&
            (trimmed.contains('<html') ||
                trimmed.contains('<head') ||
                trimmed.contains('<body')));
    if (isHtml && stage != '搜索') {
      return const DiagnosticAnalysisResult(
        category: '',
        title: '正常',
        message: '',
        advice: '',
        code: '',
      );
    }

    if (body.length <= 12 * 1024 * 1024) {
      try {
        final parsed = jsonDecode(body);
        if (parsed is! Map) {
          return DiagnosticAnalysisResult(
            category: 'DATA_PARSE',
            title: '数据格式异常',
            message: '响应数据非预期 JSON 对象',
            advice: '接口返回数据格式异常，请复制报告反馈。',
            code: 'INVALID_RESPONSE',
          );
        }
        final code = safeCode(
          parsed['code'] ?? parsed['Code'] ?? parsed['status_code'],
        );
        if (code.isNotEmpty && code != '0') {
          return DiagnosticAnalysisResult(
            category: 'BUSINESS',
            title: '业务接口拒绝',
            message: '接口返回业务错误码: $code',
            advice: '服务端业务逻辑拒绝处理当前请求，请稍后重试。',
            code: 'BUSINESS_REJECTED',
            businessCode: code,
          );
        }
        if (stage == '游客注册' &&
            (![parsed['device_id_str'], parsed['install_id_str']].every(
              (value) =>
                  value is String && RegExp(r'^\d{10,24}$').hasMatch(value),
            ))) {
          return const DiagnosticAnalysisResult(
            category: 'BUSINESS',
            title: '游客注册失败',
            message: '未获取到有效的游客设备标识',
            advice: '游客注册失败，请检查 log.snssdk.com 是否被 DNS 或代理规则拦截。',
            code: 'GUEST_REGISTRATION_FAILED',
          );
        }
        if (stage == '搜索') {
          final tabs = parsed['search_tabs'];
          if (tabs is! List) {
            return const DiagnosticAnalysisResult(
              category: 'DATA_PARSE',
              title: '搜索返回结构异常',
              message: '搜索响应缺少 search_tabs 字段',
              advice: '接口返回的搜索结构异常，请导出日志反馈。',
              code: 'INVALID_RESPONSE',
            );
          }
          final hasDrama = tabs.whereType<Map>().any(
            (tab) =>
                tab['tab_type'] == 29 || ['剧集', '短剧'].contains(tab['title']),
          );
          final hasVideos = tabs.whereType<Map>().any(
            (tab) => (tab['data'] is List ? tab['data'] as List : [])
                .whereType<Map>()
                .any(
                  (row) =>
                      row['video_data'] is List &&
                      (row['video_data'] as List).isNotEmpty,
                ),
          );
          if (!hasDrama && !hasVideos) {
            return DiagnosticAnalysisResult(
              category: 'DATA_PARSE',
              title: '官方未提供短剧分类',
              message: 'HTTP 与业务码正常，但返回分类中没有短剧数据',
              advice: adviceForCode('SEARCH_TAB_MISSING'),
              code: 'SEARCH_TAB_MISSING',
              businessCode: code,
            );
          }
        }
      } catch (e) {
        return DiagnosticAnalysisResult(
          category: 'DATA_PARSE',
          title: 'JSON 解析异常',
          message: '响应内容无法解析为 JSON: ${_sanitizeErrorMessage(e.toString())}',
          advice: '服务器可能返回了 HTML 错误页或加密内容，请复制报告反馈。',
          code: 'INVALID_RESPONSE',
        );
      }
    }

    return const DiagnosticAnalysisResult(
      category: '',
      title: '正常',
      message: '',
      advice: '',
      code: '',
    );
  }

  static String networkCode(Object error, {bool timedOut = false}) =>
      analyzeError(error, timedOut: timedOut).code;

  SourceDiagnosticEntry? record({
    required String url,
    required String context,
    required int elapsedMs,
    int status = 0,
    String body = '',
    String errorCode = '',
    Object? error,
    Map<String, String> headers = const {},
    String method = 'GET',
    String sessionStatus = '',
    bool timedOut = false,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final stage = stageFor(uri);
    if (stage == null) return null;

    Map? structure;
    if (body.length <= 12 * 1024 * 1024) {
      try {
        final value = jsonDecode(body);
        if (value is Map) structure = value;
      } catch (_) {}
    }
    var code = safeCode(
      structure?['code'] ?? structure?['Code'] ?? structure?['status_code'],
    );
    var failure = safeCode(errorCode);
    DiagnosticAnalysisResult? analysis;

    if (error != null) {
      analysis = analyzeError(error, url: url, timedOut: timedOut);
      failure = analysis.code;
    } else if (failure.isNotEmpty) {
      analysis = DiagnosticAnalysisResult(
        category: failure,
        title: failure,
        message: failure,
        advice: adviceForCode(failure),
        code: failure,
      );
    } else if (status != 0 || body.isNotEmpty) {
      final res = analyzeHttpResponse(status, body, url: url, stage: stage);
      if (res.code.isNotEmpty) {
        analysis = res;
        failure = res.code;
        code = res.businessCode;
      }
    }

    final responseHeaders = headers.map(
      (key, value) => MapEntry(key.toLowerCase(), value),
    );
    final rawLogId =
        responseHeaders['x-tt-logid'] ??
        responseHeaders['x-tt-traceid'] ??
        responseHeaders['x-ss-req-ticket'] ??
        '';
    final entry = SourceDiagnosticEntry(
      at: DateTime.now().toUtc(),
      context: context,
      stage: stage,
      host: uri.host,
      url: desensitizeUrl(url),
      method: method,
      status: status,
      businessCode: code,
      errorCode: failure,
      logId: RegExp(r'^[A-Za-z0-9_.:-]{1,160}$').hasMatch(rawLogId)
          ? rawLogId
          : '',
      errorCategory: analysis?.category ?? '',
      errorTitle: analysis?.title ?? '',
      errorMessage: redact(analysis?.message ?? ''),
      advice: analysis?.advice ?? '',
      elapsedMs: elapsedMs,
      responseSnippet: responseSummary(body),
      searchTabsSummary: searchTabsSummary(structure),
      sessionStatus: sessionStatus,
    );
    add(entry);
    return entry;
  }

  static String adviceForCode(String code) {
    if (code == 'DNS') {
      return '域名解析失败，请检查 DNS、去广告规则（如 AdGuard）或分流代理是否拦截，并用手机热点对照。';
    }
    return switch (code) {
      'SEARCH_TAB_MISSING' => '官方连接成功但未提供短剧分类，请导出日志并对照不同网络；仅凭此响应无法确定地区限制。',
      'INVALID_SEARCH_CURSOR' => '官方搜索游标未推进，请重新搜索；持续出现时导出日志反馈。',
      'SEARCH_EMPTY' => '诊断搜索未取得样本，尚未验证分页、详情与播放解析，请导出日志反馈。',
      'CANCELLED' => '操作已取消，可重新发起请求。',
      'TIMEOUT' => '请求超时，可换网络后重新检测。',
      'TLS' => '安全连接失败，请检查设备时间和网络证书或代理。',
      'CONNECTION' => '连接失败，可检查网络、代理并用手机热点对照。',
      'HTTP_403' ||
      'HTTP_429' ||
      'BUSINESS_REJECTED' => '服务端拒绝了请求；请保留报告，稍后或换网络对照。',
      'INVALID_RESPONSE' ||
      'GUEST_REGISTRATION_FAILED' => '接口返回的数据不符合预期，请复制报告反馈。',
      'EMPTY_RESPONSE' ||
      'RESPONSE_NOT_UTF8' => '接口未返回可用正文，请在同一设备用原网络和手机热点作对照，并导出诊断日志。',
      'MISSING_EPISODE' => '该剧暂无可用分集或已在官方站源下线，建议更换剧目播放。',
      'NO_STREAM_URL' => '官方媒体播放地址提取失败，建议尝试其他分集或稍后重试。',
      'JS_EXECUTION' => 'JS 脚本执行异常，请复制脱敏报告协助排查。',
      _ => '请结合失败阶段、HTTP 状态和错误说明排查。',
    };
  }

  static String advice(SourceDiagnosticEntry entry) {
    if (entry.advice.isNotEmpty) return entry.advice;
    return adviceForCode(entry.errorCode);
  }

  /// 过滤并脱敏错误消息
  static String desensitizeUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return '[无效地址]';
    const visible = {
      'tab_type',
      'offset',
      'count',
      'is_first_enter_search',
      'search_source',
      'use_correct',
      'use_lynx',
      'version_code',
      'language',
    };
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: uri.hasQuery
          ? uri.queryParameters.map(
              (key, value) => MapEntry(
                key,
                visible.contains(key.toLowerCase()) ? value : '[已隐藏]',
              ),
            )
          : null,
    ).toString();
  }

  static String redact(String raw) {
    return raw
        .replaceAllMapped(
          RegExp(
            r'\b(?:Cookie|Set-Cookie|Authorization|Proxy-Authorization)\s*[:=]\s*[^\r\n]+',
            caseSensitive: false,
          ),
          (_) => '[请求凭据已隐藏]',
        )
        .replaceAllMapped(
          RegExp(r'''https?://[^\s<>"']+'''),
          (match) => desensitizeUrl(match[0]!),
        )
        .replaceAllMapped(
          RegExp(
            r'''("?(?:device_id(?:_str)?|install_id(?:_str)?|iid|openudid|cdid|cookie|authorization|access_token|refresh_token|session_id|token|password|query|keyword|search_word)"?\s*[:=]\s*)("[^"]*"|[^\s,;&]+)''',
            caseSensitive: false,
          ),
          (match) => '${match[1]}[已隐藏]',
        );
  }

  static String searchTabsSummary(Map? structure) {
    final tabs = structure?['search_tabs'];
    if (tabs is! List) return '';
    return tabs
        .whereType<Map>()
        .map((tab) {
          final title = (tab['title'] ?? tab['tab_name'] ?? '').toString();
          final rows = tab['data'] is List ? (tab['data'] as List).length : 0;
          return '${tab['tab_type']}:${title.substring(0, title.length.clamp(0, 30))}($rows条)';
        })
        .join(', ');
  }

  static String responseSummary(String body) {
    if (body.isEmpty) return '';
    final bytes = utf8.encode(body).length;
    if (body.length <= 12 * 1024 * 1024) {
      try {
        final value = jsonDecode(body);
        if (value is Map) {
          final tabs = value['search_tabs'];
          final summary = jsonEncode({
            'bytes': bytes,
            'keys': value.keys.map((e) => e.toString()).take(40).toList(),
            'code': safeCode(
              value['code'] ?? value['Code'] ?? value['status_code'],
            ),
            if (tabs is List)
              'search_tabs': tabs.whereType<Map>().map((tab) {
                final rows = tab['data'] is List
                    ? (tab['data'] as List).whereType<Map>()
                    : <Map>[];
                return {
                  'tab_type': tab['tab_type'],
                  'rows': rows.length,
                  'videos': rows.fold<int>(
                    0,
                    (n, row) =>
                        n +
                        (row['video_data'] is List
                            ? (row['video_data'] as List).length
                            : 0),
                  ),
                  'next_offset': tab['next_offset'],
                  'has_more': tab['has_more'],
                };
              }).toList(),
          });
          return summary.substring(0, summary.length.clamp(0, 2000));
        }
      } catch (_) {}
    }
    return '非 JSON 响应，$bytes 字节';
  }

  static String _sanitizeErrorMessage(String message) {
    final sanitized = redact(message).trim();
    return sanitized.length > 200
        ? '${sanitized.substring(0, 197)}...'
        : sanitized;
  }

  /// 生成详尽格式化的脱敏诊断报告
  String report({required String version, required String sourceHash}) {
    final failures = _entries.where((e) => e.failed).toList();
    final successes = _entries.where((e) => !e.failed).toList();

    final buffer = StringBuffer();
    buffer.writeln('========================================');
    buffer.writeln('          THL 网络与数据源详细诊断报告     ');
    buffer.writeln('========================================');
    buffer.writeln('【基本信息】');
    buffer.writeln('  - 应用版本: $version');
    buffer.writeln(
      '  - 操作系统: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    buffer.writeln('  - 数据源指纹: hongguo · SHA256 $sourceHash');
    buffer.writeln(
      '  - 系统地区: ${Platform.localeName} · 时区: ${DateTime.now().timeZoneName}',
    );
    buffer.writeln('  - 诊断时间: ${DateTime.now().toUtc().toIso8601String()}');
    for (final line
        in networkEgress?.reportLines ?? ['  - 出口 IP: 尚未检测，请打开数据源诊断或点击开始检测']) {
      buffer.writeln(line);
    }
    buffer.writeln('  - 数据安全说明: 报告仅含脱敏诊断记录，不含设备唯一标识、Token、Cookie 及响应原文');
    buffer.writeln();

    buffer.writeln('【诊断概况】');
    buffer.writeln('  - 总记录数: ${_entries.length} 项');
    buffer.writeln('  - 正常通过: ${successes.length} 项');
    buffer.writeln('  - 失败异常: ${failures.length} 项');
    buffer.writeln(
      '  - 整体判定: ${_entries.isEmpty
          ? "尚未检测"
          : failures.isEmpty
          ? "记录内未发现失败；请结合已执行阶段判断"
          : "✗ 存在异常，具体原因见下方分析"}',
    );
    buffer.writeln();

    if (failures.isNotEmpty) {
      buffer.writeln('========================================');
      buffer.writeln('          【失败原因详细分析】            ');
      buffer.writeln('========================================');
      for (var i = 0; i < failures.length; i++) {
        final f = failures[i];
        buffer.writeln('【问题 ${i + 1}】阶段: ${f.stage}');
        buffer.writeln('  - 判定结论: ${f.displayTitle}');
        if (f.errorCategory.isNotEmpty) {
          buffer.writeln('  - 错误分类: ${f.errorCategory}');
        }
        if (f.host.isNotEmpty) buffer.writeln('  - 涉及域名: ${f.host}');
        if (f.status > 0) buffer.writeln('  - HTTP 状态: ${f.status}');
        if (f.errorMessage.isNotEmpty) {
          buffer.writeln('  - 失败原因: ${f.errorMessage}');
        }
        if (f.advice.isNotEmpty) buffer.writeln('  - 排查建议: ${f.advice}');
        buffer.writeln('  - 发生时间: ${f.at.toIso8601String()}');
        buffer.writeln('----------------------------------------');
      }
      buffer.writeln();
    }

    buffer.writeln('========================================');
    buffer.writeln('          【检测流水详情记录】            ');
    buffer.writeln('========================================');
    if (_entries.isEmpty) {
      buffer.writeln('暂无记录，请先复现问题或开始检测。');
    } else {
      for (final entry in _entries) {
        buffer.writeln(entry.toReportBlock());
      }
    }
    buffer.writeln('========================================');
    return redact(buffer.toString());
  }
}
