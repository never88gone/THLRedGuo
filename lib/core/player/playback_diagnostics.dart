import 'package:flutter/services.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';

String playbackFailureSummary(Object error) {
  final code = switch (error) {
    AppFailure failure when failure.code.trim().isNotEmpty => failure.code,
    AppFailure() => 'source_error',
    PlatformException failure => failure.code,
    _ => error.runtimeType.toString(),
  };
  final message = switch (error) {
    AppFailure failure => failure.message,
    PlatformException failure => failure.message ?? '原生播放器未返回错误说明',
    _ => error.toString(),
  };
  final safe = message
      .replaceAll(RegExp(r'''https?://[^\s<>"']+'''), '<url>')
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9_.+/=-]+', caseSensitive: false),
        'Bearer <redacted>',
      )
      .replaceAllMapped(
        RegExp(
          r'''\b(authorization|cookie|set-cookie|decryption_key|contentKey|access_token|refresh_token|client_secret)["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;}]+)''',
          caseSensitive: false,
        ),
        (match) => '${match[1]}=<redacted>',
      )
      .replaceAll(RegExp(r'\b[0-9a-fA-F]{32,}\b'), '<redacted>')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .trim();
  final safeCode = String.fromCharCodes(
    code.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '').runes.take(64),
  );
  return '${safeCode.isEmpty ? 'playback_error' : safeCode}: ${safe.isEmpty ? '未返回错误说明' : String.fromCharCodes(safe.runes.take(240))}';
}
