import 'package:THLRedLook/core/diagnostics/source_diagnostic_redactor.dart';

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
        '    - 请求接口: $method ${SourceDiagnosticRedactor.desensitizeUrl(url)}',
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
    return SourceDiagnosticRedactor.redact(buffer.toString().trimRight());
  }
}
