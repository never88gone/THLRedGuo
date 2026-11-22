import 'dart:math' as math;
import 'package:THLRedLook/core/enhancement/video_enhancement_assets.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_mpv.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_policy.dart';

class VideoEnhancementPipeline {
  VideoEnhancementPipeline(this.mpv, this.filterLabel);

  final VideoEnhancementMpv mpv;
  final String filterLabel;

  final Set<String> _ownedShaders = <String>{};
  final Map<String, String> _originalOptions = <String, String>{};
  final Map<String, String> _appliedOptions = <String, String>{};

  void setOption(String key, String value) {
    final original = mpv.readString(key);
    if (original == null) throw VideoEnhancementFailure(key);
    _originalOptions.putIfAbsent(key, () => original);
    mpv.set(key, value);
    _appliedOptions[key] = value;
  }

  List<String> shaderList() {
    final value = mpv.read('glsl-shaders');
    if (value is! List) throw const VideoEnhancementFailure('shader-list');
    return value.whereType<String>().toList();
  }

  Future<void> applyEffects({
    required VideoEnhancementDecision selected,
    required String? shaderPath,
    required String vendor,
    required double? videoW,
    required double? videoH,
  }) async {
    if (selected.backend != VideoEnhancementBackend.original) {
      setOption('scale', 'spline36');
      setOption('dscale', 'mitchell');
      setOption('cscale', 'bilinear');
      setOption('correct-downscaling', 'yes');
      if (shaderPath != null) {
        setOption('fbo-format', 'rgba16f');
        final current = shaderList();
        _ownedShaders.add(shaderPath);
        mpv.setStrings('glsl-shaders', [...current, shaderPath]);
      } else if (selected.backend == VideoEnhancementBackend.hardware) {
        if (videoW != null && videoH != null && videoW > 0 && videoH > 0) {
          final factor = math
              .min(
                selected.output!.width / videoW,
                selected.output!.height / videoH,
              )
              .clamp(1.0, 2.0);
          mpv.command([
            'vf',
            'add',
            '@$filterLabel:d3d11vpp=scale=${factor.toStringAsFixed(6)}:scaling-mode=$vendor:format=nv12:deint=no',
          ]);
        }
      }
    }
  }

  Future<void> prepareAndApply({
    required VideoEnhancementDecision selected,
    required bool luma,
    required String vendor,
    required double? videoW,
    required double? videoH,
  }) async {
    final shader = switch (selected.backend) {
      VideoEnhancementBackend.ravu =>
        luma ? VideoEnhancementAssets.ravuLuma : VideoEnhancementAssets.ravuRgb,
      VideoEnhancementBackend.fsrcnnx => VideoEnhancementAssets.fsrcnnx,
      VideoEnhancementBackend.anime => VideoEnhancementAssets.anime,
      _ => null,
    };
    final shaderPath =
        shader == null ? null : await VideoEnhancementAssets.prepare(shader);
    await applyEffects(
      selected: selected,
      shaderPath: shaderPath,
      vendor: vendor,
      videoW: videoW,
      videoH: videoH,
    );
  }

  void clearEffects() {
    Object? failure;
    try {
      if (_ownedShaders.isNotEmpty) {
        final current = shaderList();
        final remaining = current
            .where((item) => !_ownedShaders.contains(item))
            .toList();
        if (current.length != remaining.length) {
          mpv.setStrings('glsl-shaders', remaining);
        }
      }
    } catch (error) {
      failure = error;
    }
    try {
      final filters = mpv.read('vf');
      if (filters is List &&
          filters.any((item) => item is Map && item['label'] == filterLabel)) {
        mpv.command(['vf', 'remove', '@$filterLabel']);
      }
    } catch (error) {
      failure ??= error;
    }
    for (final entry in _appliedOptions.entries.toList().reversed) {
      try {
        if (mpv.readString(entry.key) == entry.value) {
          mpv.set(entry.key, _originalOptions[entry.key]!);
        }
        _appliedOptions.remove(entry.key);
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }
}
