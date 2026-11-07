import 'package:flutter/services.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';

/// 播放器实时技术指标与诊断信息快照
class PlaybackTechnicalDiagnostics {
  const PlaybackTechnicalDiagnostics({
    required this.playerEngine,
    required this.decoderName,
    required this.isHardwareAccelerated,
    this.videoWidth,
    this.videoHeight,
    this.fps,
    this.droppedFrames = 0,
    this.bufferDuration = Duration.zero,
    this.bufferingEventsCount = 0,
    this.requestedQuality = 0,
    this.actualQuality = 0,
    this.availableQualities = const [],
    this.isEncrypted = false,
    this.mediaHost,
    this.timestamp,
  });

  final String playerEngine;
  final String decoderName;
  final bool isHardwareAccelerated;
  final int? videoWidth;
  final int? videoHeight;
  final double? fps;
  final int droppedFrames;
  final Duration bufferDuration;
  final int bufferingEventsCount;
  final int requestedQuality;
  final int actualQuality;
  final List<int> availableQualities;
  final bool isEncrypted;
  final String? mediaHost;
  final DateTime? timestamp;

  String get videoSizeText {
    if (videoWidth != null && videoHeight != null && videoWidth! > 0 && videoHeight! > 0) {
      return '${videoWidth}x$videoHeight';
    }
    return '检测中';
  }

  String get qualityMatchSummary {
    final req = requestedQuality > 0 ? '${requestedQuality}P' : '自动（优先高清）';
    final act = actualQuality > 0 ? '${actualQuality}P' : '自动匹配';
    if (requestedQuality > 0 && actualQuality > 0 && requestedQuality != actualQuality) {
      final availStr = availableQualities.isEmpty
          ? act
          : availableQualities.map((q) => '${q}P').join('/');
      return '$req -> 降档/自动匹配至 $act (当前集提供: $availStr)';
    }
    return '$act (请求: $req)';
  }

  String toDiaryLog() {
    final size = videoSizeText;
    final fpsStr = fps != null && fps! > 0 ? '${fps!.toStringAsFixed(1)}fps' : '未知';
    final hw = isHardwareAccelerated ? '硬解生效' : '软解';
    final buf = '${(bufferDuration.inMilliseconds / 1000).toStringAsFixed(1)}s';
    final enc = isEncrypted ? '加密' : '明文';
    return '[Diag] 后端=$playerEngine | 解码=$decoderName ($hw) | 画面=$size@$fpsStr | 掉帧=$droppedFrames | 缓冲=$buf(卡顿$bufferingEventsCount次) | 档位=[$qualityMatchSummary] | 流=$enc(host=${mediaHost ?? "未知"})';
  }

  String toFormattedReport() {
    final buffer = StringBuffer();
    buffer.writeln('【播放实时技术指标与硬件诊断】');
    buffer.writeln('• 播放器引擎: $playerEngine');
    buffer.writeln('• 解码器状态: $decoderName (${isHardwareAccelerated ? "硬件加速已生效" : "软件解码/兼容模式"})');
    buffer.writeln('• 实际视频尺寸: $videoSizeText');
    buffer.writeln('• 画面帧率: ${fps != null && fps! > 0 ? "${fps!.toStringAsFixed(1)} fps" : "未知"}');
    buffer.writeln('• 呈现丢帧统计: $droppedFrames 帧');
    buffer.writeln('• 缓冲健康状态: ${(bufferDuration.inMilliseconds / 1000).toStringAsFixed(1)} 秒 (触发缓冲中断 $bufferingEventsCount 次)');
    buffer.writeln('• 清晰度对应: $qualityMatchSummary');
    buffer.writeln('• 流媒体属性: ${isEncrypted ? "DRM/AES-128加密流" : "明文直链"} · CDN Host: ${mediaHost ?? "未知"}');
    return buffer.toString().trim();
  }
}

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
