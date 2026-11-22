import 'dart:convert';
import 'dart:io';

import 'package:THLRedLook/core/diagnostics/network_egress_lookup.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_entry.dart';
import 'package:THLRedLook/core/js/hongguo_playback_profile.dart';

class SourceDiagnosticRedactor {
  const SourceDiagnosticRedactor();

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
            r'''("?(?:configuration|common_key|sign_key|mLicensetStr|x[-_](?:gorgon|helios|medusa|argus|ladon)|device_id(?:_str)?|install_id(?:_str)?|iid|openudid|cdid|cookie|authorization|access_token|refresh_token|session_id|token|password|query|keyword|search_word)"?\s*[:=]\s*)("[^"]*"|[^\s,;&]+)''',
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

  static String responseSummary(String body, {String Function(Object?)? safeCode}) {
    if (body.isEmpty) return '';
    final bytes = utf8.encode(body).length;
    if (body.length <= 12 * 1024 * 1024) {
      try {
        final value = jsonDecode(body);
        if (value is Map) {
          final tabs = value['search_tabs'];
          final rawCode = value['code'] ?? value['Code'] ?? value['status_code'];
          final code = safeCode != null ? safeCode(rawCode) : (rawCode?.toString() ?? '');
          final summary = jsonEncode({
            'bytes': bytes,
            'keys': value.keys.map((e) => e.toString()).take(40).toList(),
            'code': code,
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

  static String sanitizeErrorMessage(String message) {
    final sanitized = redact(message).trim();
    return sanitized.length > 200
        ? '${sanitized.substring(0, 197)}...'
        : sanitized;
  }

  static String generateReport({
    required List<SourceDiagnosticEntry> entries,
    required String version,
    required String sourceHash,
    NetworkEgressResult? networkEgress,
  }) {
    final failures = entries.where((e) => e.failed).toList();
    final successes = entries.where((e) => !e.failed).toList();

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
    if (HongguoPlaybackProfile.supported) {
      buffer.writeln('  - 签名方式: ${HongguoPlaybackProfile.diagnosticSummary}');
    }
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
    buffer.writeln('  - 总记录数: ${entries.length} 项');
    buffer.writeln('  - 正常通过: ${successes.length} 项');
    buffer.writeln('  - 失败异常: ${failures.length} 项');
    buffer.writeln(
      '  - 整体判定: ${entries.isEmpty
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
    if (entries.isEmpty) {
      buffer.writeln('暂无记录，请先复现问题或开始检测。');
    } else {
      for (final entry in entries) {
        buffer.writeln(entry.toReportBlock());
      }
    }
    buffer.writeln('========================================');
    return redact(buffer.toString());
  }
}
