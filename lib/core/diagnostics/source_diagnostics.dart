import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:THLRedLook/core/diagnostics/diagnostic_analysis_result.dart';
import 'package:THLRedLook/core/diagnostics/network_egress_lookup.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_analyzer.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_entry.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostic_redactor.dart';

export 'package:THLRedLook/core/diagnostics/diagnostic_analysis_result.dart';
export 'package:THLRedLook/core/diagnostics/source_diagnostic_analyzer.dart';
export 'package:THLRedLook/core/diagnostics/source_diagnostic_entry.dart';
export 'package:THLRedLook/core/diagnostics/source_diagnostic_redactor.dart';

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

  static String safeCode(Object? value) =>
      SourceDiagnosticAnalyzer.safeCode(value);

  static String? stageFor(Uri uri) => SourceDiagnosticAnalyzer.stageFor(uri);

  static DiagnosticAnalysisResult analyzeError(
    Object error, {
    String url = '',
    bool timedOut = false,
  }) =>
      SourceDiagnosticAnalyzer.analyzeError(
        error,
        url: url,
        timedOut: timedOut,
      );

  static DiagnosticAnalysisResult analyzeHttpResponse(
    int status,
    String body, {
    String url = '',
    String stage = '',
  }) =>
      SourceDiagnosticAnalyzer.analyzeHttpResponse(
        status,
        body,
        url: url,
        stage: stage,
      );

  static String networkCode(Object error, {bool timedOut = false}) =>
      SourceDiagnosticAnalyzer.networkCode(error, timedOut: timedOut);

  static String adviceForCode(String code) =>
      SourceDiagnosticAnalyzer.adviceForCode(code);

  static String advice(SourceDiagnosticEntry entry) {
    if (entry.advice.isNotEmpty) return entry.advice;
    return adviceForCode(entry.errorCode);
  }

  static String desensitizeUrl(String raw) =>
      SourceDiagnosticRedactor.desensitizeUrl(raw);

  static String redact(String raw) => SourceDiagnosticRedactor.redact(raw);

  static String searchTabsSummary(Map? structure) =>
      SourceDiagnosticRedactor.searchTabsSummary(structure);

  static String responseSummary(String body) =>
      SourceDiagnosticRedactor.responseSummary(body, safeCode: safeCode);

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

  String report({required String version, required String sourceHash}) =>
      SourceDiagnosticRedactor.generateReport(
        entries: _entries,
        version: version,
        sourceHash: sourceHash,
        networkEgress: networkEgress,
      );
}
