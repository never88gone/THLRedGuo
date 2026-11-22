import 'dart:ui';

import 'package:media_kit/media_kit.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_mpv.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_policy.dart';

class VideoEnhancementMonitor {
  VideoEnhancementMonitor(this.filterLabel);

  final String filterLabel;
  final List<double> _renderSamples = [];
  int? _previousDrops;
  DateTime? _previousSample;
  DateTime? _overloadedSince;

  void reset() {
    _renderSamples.clear();
    _previousDrops = null;
    _previousSample = null;
    _overloadedSince = null;
  }

  bool isOwnPass(String description, VideoEnhancementBackend backend) =>
      switch (backend) {
        VideoEnhancementBackend.ravu => description.contains('RAVU'),
        VideoEnhancementBackend.anime => description.contains('Anime4K'),
        VideoEnhancementBackend.fsrcnnx => RegExp(
          r'feature map [12]|mapping [1-4]_[12]|sub-band residuals [12]|sub-pixel convolution 1|aggregation',
        ).hasMatch(description),
        _ => false,
      };

  bool checkSizeMatches({
    required VideoEnhancementMpv mpv,
    required Size? actual,
    required Size? target,
  }) {
    if (actual == null || target == null) return false;
    final surface = mpv.read('osd-dimensions');
    final surfaceWidth = surface is Map ? surface['w'] : null;
    final surfaceHeight = surface is Map ? surface['h'] : null;
    return (actual.width - target.width).abs() <= 2 &&
        (actual.height - target.height).abs() <= 2 &&
        surfaceWidth is num &&
        surfaceHeight is num &&
        (surfaceWidth - target.width).abs() <= 2 &&
        (surfaceHeight - target.height).abs() <= 2;
  }

  bool checkEffectFound({
    required VideoEnhancementMpv mpv,
    required VideoEnhancementDecision selected,
    required List fresh,
    required bool luma,
    required bool gpu,
  }) {
    final descriptions = fresh
        .whereType<Map>()
        .map((item) => item['desc']?.toString() ?? '')
        .join('\n');
    return switch (selected.backend) {
      VideoEnhancementBackend.ravu => descriptions.contains(
        luma ? 'RAVU-Lite-AR (step2' : 'RAVU (step4',
      ),
      VideoEnhancementBackend.anime =>
        descriptions.contains('Anime4K') &&
            descriptions.contains('Depth-to-Space'),
      VideoEnhancementBackend.fsrcnnx =>
        descriptions.contains('feature map') &&
            descriptions.contains('aggregation'),
      VideoEnhancementBackend.hardware => hardwareFramesChanged(
        mpv: mpv,
        selected: selected,
      ),
      _ => gpu,
    };
  }

  ({bool confirmed, int misses, VideoEnhancementFailure? failure})
  verifyConfirmation({
    required bool sizeMatches,
    required bool effectFound,
    required bool isPlaying,
    required bool isBuffering,
    required int currentMisses,
  }) {
    if (sizeMatches && effectFound) {
      return (confirmed: true, misses: 0, failure: null);
    }
    if (isPlaying && !isBuffering) {
      final nextMisses = currentMisses + 1;
      if (nextMisses >= 5) {
        return (
          confirmed: false,
          misses: nextMisses,
          failure: VideoEnhancementFailure(
            sizeMatches ? 'render-pass' : 'output-size',
          ),
        );
      }
      return (confirmed: false, misses: nextMisses, failure: null);
    }
    return (confirmed: false, misses: currentMisses, failure: null);
  }

  bool hardwareFramesChanged({
    required VideoEnhancementMpv mpv,
    required VideoEnhancementDecision selected,
  }) {
    final output = mpv.read('video-out-params');
    final filters = mpv.read('vf');
    if (output is! Map || filters is! List || selected.output == null) {
      return false;
    }
    final width = (output['w'] as num?)?.toDouble() ?? 0;
    final height = (output['h'] as num?)?.toDouble() ?? 0;
    return filters.any(
          (item) =>
              item is Map &&
              item['label'] == filterLabel &&
              item['enabled'] != false,
        ) &&
        (width - selected.output!.width).abs() <= 4 &&
        (height - selected.output!.height).abs() <= 4;
  }

  bool checkOverloaded({
    required Player player,
    required VideoEnhancementMpv mpv,
    required VideoEnhancementDecision selected,
    required List fresh,
    required bool confirmed,
    required bool comparing,
    required DateTime ignorePerformanceUntil,
  }) {
    final now = DateTime.now();
    final state = player.state;
    if (!confirmed ||
        !state.playing ||
        state.buffering ||
        comparing ||
        state.rate > 1.01 ||
        now.isBefore(ignorePerformanceUntil)) {
      _previousSample = null;
      _previousDrops = null;
      _overloadedSince = null;
      return false;
    }
    var fpsValue = mpv.read('container-fps');
    if (fpsValue is! num || fpsValue <= 0) {
      fpsValue = mpv.read('estimated-vf-fps');
    }
    final fps = fpsValue is num ? fpsValue.toDouble() : 0.0;
    if (!fps.isFinite || fps <= 0 || fps > 240) return false;
    var ownMs = 0.0;
    var timed = false;
    for (final pass in fresh.whereType<Map>()) {
      if (!isOwnPass(pass['desc']?.toString() ?? '', selected.backend)) {
        continue;
      }
      final last = pass['last'];
      if (last is num && last >= 0) {
        ownMs += last / 1000000;
        timed = true;
      }
    }
    if (timed && ownMs.isFinite) {
      _renderSamples.add(ownMs);
      if (_renderSamples.length > 20) _renderSamples.removeAt(0);
    }
    final samples = [..._renderSamples]..sort();
    final p95 = samples.isEmpty
        ? 0.0
        : samples[((samples.length - 1) * .95).ceil()];
    var overloaded = samples.length >= 5 && p95 > 1000 / fps / state.rate * .25;
    final rawDrops = mpv.read('frame-drop-count');
    if (rawDrops is num) {
      final drops = rawDrops.toInt();
      final previous = _previousDrops;
      final previousTime = _previousSample;
      if (previous != null && previousTime != null && drops >= previous) {
        final seconds = now.difference(previousTime).inMilliseconds / 1000;
        if (seconds >= 1 && seconds <= 5) {
          overloaded = overloaded || (drops - previous) / (fps * seconds) > .01;
        }
      }
      _previousDrops = drops;
      _previousSample = now;
    }
    if (!overloaded) {
      _overloadedSince = null;
      return false;
    }
    _overloadedSince ??= now;
    if (now.difference(_overloadedSince!) < const Duration(seconds: 10)) {
      return false;
    }
    return true;
  }
}
