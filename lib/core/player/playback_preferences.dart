import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';
import 'package:THLRedLook/models/danmaku/danmaku_models.dart';

const playbackSpeeds = [.5, .75, 1.0, 1.25, 1.5, 2.0, 3.0];

enum PlayerFillStyle {
  black('纯黑', '传统经典纯黑底色，沉浸无干扰'),
  theme('目前应该使用的主题色', '融合当前应用深色或浅色主题背景色'),
  cover('短剧的图片', '提取当前播放短剧海报进行氛围高斯模糊填充');

  const PlayerFillStyle(this.label, this.description);
  final String label;
  final String description;
}

enum PlaybackDecoderMode {
  hardware('极速硬解优先', '启用 GPU/MediaCodec 硬件加速，大屏低功耗更流畅'),
  compatible('兼容稳定模式', 'MediaKit 兼容软解引擎，专治黑屏无画面、声音正常但无图像');

  const PlaybackDecoderMode(this.label, this.description);
  final String label;
  final String description;
}

class PlaybackPreferences {
  const PlaybackPreferences({
    this.speed = 1,
    this.quality = 0,
    this.autoAdvance = true,
    this.pictureInPicture = true,
    this.danmaku = true,
    this.danmakuStyle = const DanmakuStyle(),
    this.preload = true,
    this.enhancement = const VideoEnhancementPreferences(),
    this.decoderMode = PlaybackDecoderMode.hardware,
    this.volume = 100.0,
    this.fillStyle = PlayerFillStyle.black,
    this.backgroundAudio = true,
    this.episodeTransition = true,
    this.quietEpisodeAdvance = true,
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
  final double volume;
  final PlayerFillStyle fillStyle;
  final bool backgroundAudio;
  final bool episodeTransition;
  final bool quietEpisodeAdvance;

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
    double? volume,
    PlayerFillStyle? fillStyle,
    bool? backgroundAudio,
    bool? episodeTransition,
    bool? quietEpisodeAdvance,
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
    volume: volume ?? this.volume,
    fillStyle: fillStyle ?? this.fillStyle,
    backgroundAudio: backgroundAudio ?? this.backgroundAudio,
    episodeTransition: episodeTransition ?? this.episodeTransition,
    quietEpisodeAdvance: quietEpisodeAdvance ?? this.quietEpisodeAdvance,
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
    'volume': volume,
    'fillStyle': fillStyle.name,
    'backgroundAudio': backgroundAudio,
    'episodeTransition': episodeTransition,
    'quietEpisodeAdvance': quietEpisodeAdvance,
  };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> value) {
    final speed = (value['speed'] as num? ?? 1).toDouble();
    final quality = value['quality'] as int? ?? 0;
    final autoAdvance = value['autoAdvance'] as bool? ?? true;
    final pictureInPicture = value['pictureInPicture'] as bool? ?? true;
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
    final volume = (value['volume'] as num? ?? 100.0).toDouble().clamp(0.0, 100.0);
    final fillStyleStr = value['fillStyle'] as String?;
    final fillStyle = PlayerFillStyle.values.firstWhere(
      (e) => e.name == fillStyleStr,
      orElse: () => PlayerFillStyle.black,
    );
    final backgroundAudio = value['backgroundAudio'] as bool? ?? true;
    final episodeTransition = value['episodeTransition'] as bool? ?? true;
    final quietEpisodeAdvance = value['quietEpisodeAdvance'] as bool? ?? true;
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
      volume: volume,
      fillStyle: fillStyle,
      backgroundAudio: backgroundAudio,
      episodeTransition: episodeTransition,
      quietEpisodeAdvance: quietEpisodeAdvance,
    );
  }
}
