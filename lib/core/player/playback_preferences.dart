import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';
import 'package:THLRedLook/models/danmaku/danmaku_models.dart';

const playbackSpeeds = [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0];

enum PlaybackDecoderMode {
  hardware('极速硬解优先', '启用 GPU/MediaCodec 硬件加速，大屏低功耗更流畅'),
  compatible('兼容稳定模式', '单通道串行硬解防冲突，解决老旧芯片黑屏与拖慢');

  const PlaybackDecoderMode(this.label, this.description);
  final String label;
  final String description;
}

class PlaybackPreferences {
  const PlaybackPreferences({
    this.speed = 1,
    this.quality = 0,
    this.autoAdvance = true,
    this.pictureInPicture = false,
    this.danmaku = true,
    this.danmakuStyle = const DanmakuStyle(),
    this.preload = true,
    this.enhancement = const VideoEnhancementPreferences(),
    this.decoderMode = PlaybackDecoderMode.hardware,
  });

  final double speed;
  final int quality;
  final bool autoAdvance;
  final bool pictureInPicture;
  final bool danmaku;
  final DanmakuStyle danmakuStyle;
  final bool preload;
  final VideoEnhancementPreferences enhancement;
  final PlaybackDecoderMode decoderMode;

  PlaybackPreferences copyWith({
    double? speed,
    int? quality,
    bool? autoAdvance,
    bool? pictureInPicture,
    bool? danmaku,
    DanmakuStyle? danmakuStyle,
    bool? preload,
    VideoEnhancementPreferences? enhancement,
    PlaybackDecoderMode? decoderMode,
  }) => PlaybackPreferences(
    speed: speed ?? this.speed,
    quality: quality ?? this.quality,
    autoAdvance: autoAdvance ?? this.autoAdvance,
    pictureInPicture: pictureInPicture ?? this.pictureInPicture,
    danmaku: danmaku ?? this.danmaku,
    danmakuStyle: danmakuStyle ?? this.danmakuStyle,
    preload: preload ?? this.preload,
    enhancement: enhancement ?? this.enhancement,
    decoderMode: decoderMode ?? this.decoderMode,
  );

  Map<String, dynamic> toJson() => {
    'speed': speed,
    'quality': quality,
    'autoAdvance': autoAdvance,
    'pictureInPicture': pictureInPicture,
    'danmaku': danmaku,
    'danmakuStyle': danmakuStyle.toJson(),
    'preload': preload,
    'enhancement': enhancement.toJson(),
    'decoderMode': decoderMode.name,
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> value) {
    final speed = (value['speed'] as num? ?? 1).toDouble();
    final quality = value['quality'] as int? ?? 0;
    final autoAdvance = value['autoAdvance'] as bool? ?? true;
    final pictureInPicture = value['pictureInPicture'] as bool? ?? false;
    final danmaku = value['danmaku'] as bool? ?? true;
    final danmakuStyle = value['danmakuStyle'] is Map
        ? DanmakuStyle.fromJson(value['danmakuStyle'] as Map<String, dynamic>)
        : const DanmakuStyle();
    final preload = value['preload'] as bool? ?? true;
    final decoderModeStr = value['decoderMode'] as String?;
    final decoderMode = PlaybackDecoderMode.values.firstWhere(
      (e) => e.name == decoderModeStr,
      orElse: () => PlaybackDecoderMode.hardware,
    );
    if (!playbackSpeeds.contains(speed) || quality < 0 || quality > 4320) {
      throw const FormatException('播放偏好无效');
    }
    return PlaybackPreferences(
      speed: speed,
      quality: quality,
      autoAdvance: autoAdvance,
      pictureInPicture: pictureInPicture,
      danmaku: danmaku,
      danmakuStyle: danmakuStyle,
      preload: preload,
      enhancement: VideoEnhancementPreferences.fromJson(value['enhancement']),
      decoderMode: decoderMode,
    );
  }
}
