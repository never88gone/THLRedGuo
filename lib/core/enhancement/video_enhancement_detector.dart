import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/core/enhancement/video_enhancement_mpv.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_policy.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';

class VideoEnhancementDetector {
  VideoEnhancementDetector({this.filterLabel = 'duanju_vsr'});

  static const _device = MethodChannel('duanju/device');
  final String filterLabel;

  final Set<String> recentEnhancementErrors = <String>{};
  VideoEnhancementPower power = const VideoEnhancementPower();
  bool gpu = false;
  bool luma = false;
  bool opaque8Bit = false;
  bool hardware = false;
  bool softwareRenderer = false;
  String renderer = '';
  String vendor = '';

  Future<void> readPower() async {
    try {
      final value = await _device
          .invokeMapMethod<String, dynamic>('playbackPower')
          .timeout(const Duration(seconds: 2));
      if (value != null) {
        power = VideoEnhancementPower.fromMap(value);
      }
    } catch (_) {}
  }

  bool readCapabilities({
    required VideoEnhancementMpv mpv,
    required VideoParams videoParams,
  }) {
    final oldGpu = gpu;
    final oldLuma = luma;
    final oldHardware = hardware;
    final oldOpaque8Bit = opaque8Bit;

    final vo = mpv.read('current-vo')?.toString() ?? '';
    final hwdec = mpv.read('hwdec-current')?.toString() ?? '';
    final version = mpv.read('mpv-version')?.toString() ?? '';
    final versionNumber = RegExp(r'\bv?0\.(\d+)\.').firstMatch(version);
    final recentMpv =
        versionNumber != null && (int.tryParse(versionNumber[1]!) ?? 0) >= 39;
    final passes = mpv.read('vo-passes');
    gpu =
        !softwareRenderer &&
        (vo == 'gpu' ||
            vo == 'libmpv' && (renderer.isNotEmpty || passes is Map));
    final format = videoEnhancementPixelFormat(videoParams);
    luma =
        !(Platform.isAndroid && hwdec == 'mediacodec') &&
        (format.startsWith('yuv') || format == 'nv12' || format == 'nv21');
    opaque8Bit = false;
    if (Platform.isAndroid && hwdec == 'mediacodec' && format == 'mediacodec') {
      final tracks = mpv.read('track-list');
      if (tracks is List) {
        for (final track in tracks.whereType<Map>()) {
          if (track['type'] != 'video' || track['selected'] != true) continue;
          final codec = track['codec']?.toString().toLowerCase() ?? '';
          final profile =
              track['codec-profile']?.toString().toLowerCase() ?? '';
          opaque8Bit =
              codec == 'h264' &&
                  {
                    'baseline',
                    'constrained baseline',
                    'main',
                    'extended',
                    'high',
                    'constrained high',
                  }.contains(profile) ||
              codec == 'hevc' &&
                  {'main', 'main still picture'}.contains(profile);
          break;
        }
      }
    }
    hardware =
        Platform.isWindows &&
        gpu &&
        recentMpv &&
        (vendor == 'nvidia' || vendor == 'intel') &&
        hwdec == 'd3d11va' &&
        (format == 'nv12' || format == 'yuv420p');

    return oldGpu != gpu ||
        oldLuma != luma ||
        oldHardware != hardware ||
        oldOpaque8Bit != opaque8Bit;
  }

  void processLog(
    PlayerLog log, {
    required bool circuitOpen,
    required VideoEnhancementBackend? activeBackend,
    required void Function() onRendererChanged,
    required void Function(Object error) onRenderFailed,
  }) {
    final prefix = log.prefix.toLowerCase();
    final text = log.text.toLowerCase();
    if ((prefix.contains('vo/') || prefix.contains('libmpv')) &&
        (text.contains('gl_renderer') ||
            text.contains('gl_vendor') ||
            text.contains('gl renderer') ||
            text.contains('gl vendor'))) {
      if (text.contains('renderer')) {
        renderer = log.text.length <= 512
            ? log.text
            : log.text.substring(0, 512);
        vendor = text.contains('nvidia')
            ? 'nvidia'
            : text.contains('intel')
            ? 'intel'
            : '';
      }
      softwareRenderer =
          softwareRenderer ||
          RegExp(
            r'swiftshader|llvmpipe|softpipe|software rasterizer|microsoft basic',
          ).hasMatch(text);
      onRendererChanged();
    }
    final active = activeBackend;
    if (active == null ||
        active == VideoEnhancementBackend.original ||
        circuitOpen) {
      return;
    }
    final graphics =
        prefix.contains('d3d11vpp') ||
        prefix.contains(filterLabel) ||
        prefix.contains('vo/gpu') ||
        prefix.contains('vo/libmpv');
    final failed =
        log.level == 'error' ||
        log.level == 'fatal' ||
        log.level == 'warn' &&
            RegExp(r'fail|error|unsupported|disabled').hasMatch(text);
    if (graphics && failed) {
      if (recentEnhancementErrors.length >= 16) {
        recentEnhancementErrors.clear();
      }
      recentEnhancementErrors.add(log.text.trim());
      onRenderFailed(const VideoEnhancementFailure('render'));
    }
  }

  bool handlePlaybackError(String text, {required int activeCost}) {
    final value = text.trim();
    final owned =
        recentEnhancementErrors.contains(value) ||
        activeCost > 0 &&
            RegExp(
              r'd3d11vpp|duanju_vsr|glsl.shaders|shader.*compil|compil.*shader',
              caseSensitive: false,
            ).hasMatch(value);
    if (!owned) return false;
    return true;
  }

  VideoEnhancementDecision choose({
    required VideoEnhancementPreferences preferences,
    required VideoParams parameters,
    required Size viewport,
    required bool ready,
    required bool television,
    required bool animation,
    required double rate,
    required int costLimit,
    required Set<VideoEnhancementBackend> rejected,
  }) =>
      chooseVideoEnhancement(
        preferences: preferences,
        parameters: parameters,
        viewport: viewport,
        ready: ready,
        android: Platform.isAndroid,
        television: television,
        gpu: gpu,
        luma: luma,
        hardware: hardware,
        animation: animation,
        power: power,
        rate: rate,
        costLimit: costLimit,
        rejected: rejected,
        opaque8Bit: opaque8Bit,
      );
}
