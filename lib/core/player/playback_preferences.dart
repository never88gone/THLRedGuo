import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';
import 'package:THLRedLook/models/danmaku/danmaku_models.dart';

const playbackSpeeds = [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0];

class PlaybackPreferences {
  const PlaybackPreferences({
    this.speed = 1,
    this.quality = 0,
    this.autoAdvance = true,
    this.danmaku = true,
    this.danmakuStyle = const DanmakuStyle(),
    this.preload = true,
    this.enhancement = const VideoEnhancementPreferences(),
  });

  final double speed;
  final int quality;
  final bool autoAdvance;
  final bool danmaku;
  final DanmakuStyle danmakuStyle;
  final bool preload;
  final VideoEnhancementPreferences enhancement;

  PlaybackPreferences copyWith({
    double? speed,
    int? quality,
    bool? autoAdvance,
    bool? danmaku,
    DanmakuStyle? danmakuStyle,
    bool? preload,
    VideoEnhancementPreferences? enhancement,
  }) => PlaybackPreferences(
    speed: speed ?? this.speed,
    quality: quality ?? this.quality,
    autoAdvance: autoAdvance ?? this.autoAdvance,
    danmaku: danmaku ?? this.danmaku,
    danmakuStyle: danmakuStyle ?? this.danmakuStyle,
    preload: preload ?? this.preload,
    enhancement: enhancement ?? this.enhancement,
  );

  Map<String, dynamic> toJson() => {
    'speed': speed,
    'quality': quality,
    'autoAdvance': autoAdvance,
    'danmaku': danmaku,
    'danmakuStyle': danmakuStyle.toJson(),
    'preload': preload,
    'enhancement': enhancement.toJson(),
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> value) {
    final speed = (value['speed'] as num? ?? 1).toDouble();
    final quality = value['quality'] as int? ?? 0;
    final autoAdvance = value['autoAdvance'] as bool? ?? true;
    final danmaku = value['danmaku'] as bool? ?? true;
    final danmakuStyle = value['danmakuStyle'] is Map
        ? DanmakuStyle.fromJson(value['danmakuStyle'] as Map<String, dynamic>)
        : const DanmakuStyle();
    final preload = value['preload'] as bool? ?? true;
    if (!playbackSpeeds.contains(speed) || quality < 0 || quality > 4320) {
      throw const FormatException('播放偏好无效');
    }
    return PlaybackPreferences(
      speed: speed,
      quality: quality,
      autoAdvance: autoAdvance,
      danmaku: danmaku,
      danmakuStyle: danmakuStyle,
      preload: preload,
      enhancement: VideoEnhancementPreferences.fromJson(value['enhancement']),
    );
  }
}
