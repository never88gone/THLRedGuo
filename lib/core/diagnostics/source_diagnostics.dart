import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SourceDiagnosticEntry {
  const SourceDiagnosticEntry({
    required this.at,
    required this.context,
    required this.stage,
    this.host = '',
    this.status = 0,
    this.businessCode = '',
    this.errorCode = '',
    this.elapsedMs = 0,
    this.count,
  });

  final DateTime at;
  final String context;
  final String stage;
  final String host;
  final int status;
  final String businessCode;
  final String errorCode;
  final int elapsedMs;
  final int? count;
  bool get failed => errorCode.isNotEmpty;

  String get text => [
    '${at.toIso8601String()} [$context] $stage',
    if (host.isNotEmpty) host,
    if (status > 0) 'HTTP $status',
    if (businessCode.isNotEmpty) '业务码 $businessCode',
    if (errorCode.isNotEmpty) errorCode,
    if (elapsedMs > 0) '${elapsedMs}ms',
    if (count != null) '$count 条结果',
  ].join(' · ');
}

class SourceDiagnostics extends ChangeNotifier {
  static final shared = SourceDiagnostics();
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
    return null;
  }

  static String networkCode(Object error, {bool timedOut = false}) {
    if (timedOut || error is TimeoutException) return 'TIMEOUT';
    if (error is http.RequestAbortedException) return 'CANCELLED';
    if (error is HandshakeException || error is TlsException) return 'TLS';
    final description = error.toString().toLowerCase();
    if (description.contains('failed host lookup') ||
        description.contains('name or service not known') ||
        description.contains('nodename nor servname') ||
        description.contains('could not resolve')) {
      return 'DNS';
    }
    if (description.contains('handshake') ||
        description.contains('certificate')) {
      return 'TLS';
    }
    if (error is SocketException || error is http.ClientException) {
      return 'CONNECTION';
    }
    if (error is FormatException) return 'INVALID_RESPONSE';
    return 'NETWORK_ERROR';
  }

  void record({
    required String url,
    required String context,
    required int elapsedMs,
    int status = 0,
    String body = '',
    String errorCode = '',
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final stage = stageFor(uri);
    if (stage == null) return;
    var code = '';
    var failure = safeCode(errorCode);
    if (failure.isEmpty && status != 200) failure = 'HTTP_$status';
    if (failure.isEmpty && body.length <= 2 * 1024 * 1024) {
      try {
        final parsed = jsonDecode(body);
        if (parsed is! Map) {
          failure = 'INVALID_RESPONSE';
        } else {
          code = safeCode(
            parsed['code'] ?? parsed['Code'] ?? parsed['status_code'],
          );
          if (code.isNotEmpty && code != '0') {
            failure = 'BUSINESS_REJECTED';
          } else if (stage == '游客注册' &&
              (![parsed['device_id_str'], parsed['install_id_str']].every(
                (value) =>
                    value is String && RegExp(r'^\d{10,24}$').hasMatch(value),
              ))) {
            failure = 'GUEST_REGISTRATION_FAILED';
          } else if (stage == '搜索' && parsed['search_tabs'] is! List) {
            failure = 'INVALID_RESPONSE';
          }
        }
      } catch (_) {
        failure = 'INVALID_RESPONSE';
      }
    }
    add(
      SourceDiagnosticEntry(
        at: DateTime.now().toUtc(),
        context: context,
        stage: stage,
        host: uri.host,
        status: status,
        businessCode: code,
        errorCode: failure,
        elapsedMs: elapsedMs,
      ),
    );
  }

  static String advice(SourceDiagnosticEntry entry) {
    if (entry.errorCode == 'DNS' || (entry.stage == '游客注册' && entry.failed)) {
      return '游客注册失败时，请检查 log.snssdk.com 是否被 DNS、去广告或代理规则拦截，并用手机热点对照。';
    }
    return switch (entry.errorCode) {
      'TIMEOUT' => '请求超时，可换网络后重新检测。',
      'TLS' => '安全连接失败，请检查设备时间和网络证书或代理。',
      'CONNECTION' => '连接失败，可检查网络、代理并用手机热点对照。',
      'HTTP_403' ||
      'HTTP_429' ||
      'BUSINESS_REJECTED' => '服务端拒绝了请求；请保留报告，稍后或换网络对照。',
      'INVALID_RESPONSE' ||
      'GUEST_REGISTRATION_FAILED' => '接口返回的数据不符合预期，请复制报告反馈。',
      _ => '请结合失败阶段、HTTP 状态和错误码反馈；单次检测不能判断是否被网络规则拦截。',
    };
  }

  String report({required String version, required String sourceHash}) => [
    'THL 数据源诊断',
    '应用：$version',
    '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    '数据源：hongguo · SHA256 $sourceHash',
    '报告时间：${DateTime.now().toUtc().toIso8601String()}',
    '仅含脱敏诊断信息，不含请求参数、设备标识、Cookie、签名和响应原文。',
    if (_entries.isEmpty) '暂无记录，请先复现问题或开始检测。',
    ..._entries.map((entry) => entry.text),
  ].join('\n');
}
