import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:THLRedLook/core/diagnostics/diagnostic_analysis_result.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_redactor.dart';

class SourceDiagnosticAnalyzer {
  const SourceDiagnosticAnalyzer();

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
        message:
            '与 $target 建立安全连接失败：${SourceDiagnosticRedactor.sanitizeErrorMessage(raw)}',
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
        message:
            'JS 脚本执行抛出异常: ${SourceDiagnosticRedactor.sanitizeErrorMessage(raw)}',
        advice:
            '数据源脚本运行报错，通常为脚本解析逻辑与当前数据不匹配或 JS 引擎兼容性问题，可复制报告反馈。',
        code: 'JS_EXECUTION',
      );
    }

    // 5. 格式错误
    if (error is FormatException) {
      return DiagnosticAnalysisResult(
        category: 'DATA_PARSE',
        title: '数据返回格式异常',
        message:
            '服务端响应内容格式不符合预期: ${SourceDiagnosticRedactor.sanitizeErrorMessage(raw)}',
        advice: '接口返回的数据无法被正确解析，可能是接口变动或返回了反爬拦截页。',
        code: 'INVALID_RESPONSE',
      );
    }

    return DiagnosticAnalysisResult(
      category: 'NETWORK_ERROR',
      title: '未知网络异常',
      message: SourceDiagnosticRedactor.sanitizeErrorMessage(raw),
      advice: '请结合失败阶段和错误详情反馈排查。',
      code: 'NETWORK_ERROR',
    );
  }

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
          message:
              '响应内容无法解析为 JSON: ${SourceDiagnosticRedactor.sanitizeErrorMessage(e.toString())}',
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

  static String adviceForCode(String code) {
    if (code == 'DNS') {
      return '域名解析失败，请检查 DNS、去广告规则（如 AdGuard）或分流代理是否拦截，并用手机热点对照。';
    }
    return switch (code) {
      'LOCAL_PROFILE_REQUIRED' ||
      'LOCAL_PROFILE_INVALID' => '请更新 JS 数据源后重试，持续失败时导出诊断报告。',
      'LOCAL_PROFILE_UNAVAILABLE' => '本机签名缓存暂不可访问，请稍后重试。',
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
}
