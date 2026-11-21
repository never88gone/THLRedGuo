import 'package:flutter/material.dart';

import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_settings.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/remote/remote_widgets.dart';

class TelevisionPlaybackSetting {
  const TelevisionPlaybackSetting({
    this.speed,
    this.quality,
    this.autoAdvance,
    this.danmaku,
    this.preload,
    this.enhancement,
    this.decoderMode,
  });
  final double? speed;
  final int? quality;
  final bool? autoAdvance;
  final bool? danmaku;
  final bool? preload;
  final VideoEnhancementPreferences? enhancement;
  final PlaybackDecoderMode? decoderMode;
}

class TelevisionSettingsDialog extends StatelessWidget {
  const TelevisionSettingsDialog({
    super.key,
    required this.speed,
    required this.quality,
    required this.qualities,
    required this.favorite,
    required this.onFavorite,
    this.actualQuality = 0,
    this.autoAdvance = true,
    this.danmaku = true,
    this.showDanmaku = false,
    this.danmakuStatus = '',
    this.onRetryDanmaku,
    this.preload = true,
    this.preloadStatus = '',
    this.enhancement,
    this.onCompareEnhancement,
    this.decoderMode = PlaybackDecoderMode.hardware,
  });
  final double speed;
  final int quality;
  final List<int> qualities;
  final int actualQuality;
  final bool favorite;
  final VoidCallback onFavorite;
  final bool autoAdvance;
  final bool danmaku;
  final bool showDanmaku;
  final String danmakuStatus;
  final VoidCallback? onRetryDanmaku;
  final bool preload;
  final String preloadStatus;
  final VideoEnhancementController? enhancement;
  final VoidCallback? onCompareEnhancement;
  final PlaybackDecoderMode decoderMode;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('播放设置'),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('倍速', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in playbackSpeeds)
                  RemoteButton(
                    key: ValueKey('tv-speed-$value'),
                    label: '${value}x',
                    autofocus: value == speed,
                    selected: value == speed,
                    onPressed: () => Navigator.pop(
                      context,
                      TelevisionPlaybackSetting(speed: value),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('清晰度', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                if (quality > 0 && !qualities.contains(quality) && actualQuality > 0)
                  Text(
                    '当前集未提供 ${quality}P，已自动匹配 ${actualQuality}P',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.whiteWithAlpha(0.6),
                    ),
                  )
                else if (actualQuality > 0 && actualQuality != quality)
                  Text(
                    '当前播放：${actualQuality}P',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.whiteWithAlpha(0.6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                RemoteButton(
                  key: const ValueKey('tv-quality-0'),
                  label: '自动（优先高清）',
                  selected: quality == 0,
                  onPressed: () => Navigator.pop(
                    context,
                    const TelevisionPlaybackSetting(quality: 0),
                  ),
                ),
                for (final value in qualities.where((value) => value > 0).toSet())
                  RemoteButton(
                    key: ValueKey('tv-quality-$value'),
                    label: value == quality
                        ? '${value}P'
                        : (value == actualQuality &&
                                quality > 0 &&
                                !qualities.contains(quality)
                            ? '${value}P (当前匹配)'
                            : '${value}P'),
                    selected: value == quality ||
                        (quality > 0 &&
                            !qualities.contains(quality) &&
                            value == actualQuality),
                    onPressed: () => Navigator.pop(
                      context,
                      TelevisionPlaybackSetting(quality: value),
                    ),
                  ),
                if (quality > 0 && !qualities.contains(quality))
                  RemoteButton(
                    key: ValueKey('tv-quality-$quality'),
                    label: '${quality}P (偏好锁定)',
                    selected: true,
                    onPressed: () => Navigator.pop(
                      context,
                      TelevisionPlaybackSetting(quality: quality),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('解码模式', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in PlaybackDecoderMode.values)
                  RemoteButton(
                    key: ValueKey('tv-decoder-${mode.name}'),
                    label: mode.label,
                    selected: mode == decoderMode,
                    onPressed: () => Navigator.pop(
                      context,
                      TelevisionPlaybackSetting(decoderMode: mode),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              decoderMode == PlaybackDecoderMode.hardware
                  ? '⚡ 推荐：MediaCodec 原生硬解加速，大屏低功耗、画质细腻。'
                  : '🛡️ 兼容：MediaKit 软解兼容引擎，专治黑屏无画面、老旧电视仅有声音无图像。',
              style: const TextStyle(fontSize: 13, color: AppColors.white70),
            ),
            const SizedBox(height: 20),
            if (enhancement != null)
              VideoEnhancementSettings(
                controller: enhancement!,
                television: true,
                onChanged: (value) => Navigator.pop(
                  context,
                  TelevisionPlaybackSetting(enhancement: value),
                ),
                onCompare: onCompareEnhancement ?? () {},
              ),
            if (showDanmaku) ...[
              RemoteButton(
                key: const ValueKey('tv-danmaku-enabled'),
                label: danmaku ? '弹幕：开' : '弹幕：关',
                onPressed: () => Navigator.pop(
                  context,
                  TelevisionPlaybackSetting(danmaku: !danmaku),
                ),
              ),
              const SizedBox(height: 8),
              Text(danmakuStatus, style: const TextStyle(fontSize: 14)),
              if (onRetryDanmaku != null)
                RemoteButton(
                  key: const ValueKey('tv-danmaku-retry'),
                  label: '重试弹幕',
                  onPressed: onRetryDanmaku,
                ),
              const SizedBox(height: 20),
            ],
            RemoteButton(
              key: const ValueKey('tv-auto-advance'),
              label: autoAdvance ? '自动连播：开' : '自动连播：关',
              onPressed: () => Navigator.pop(
                context,
                TelevisionPlaybackSetting(autoAdvance: !autoAdvance),
              ),
            ),
            const SizedBox(height: 16),
            RemoteButton(
              key: const ValueKey('tv-preload-enabled'),
              label: preload ? '下一集预加载：开' : '下一集预加载：关',
              onPressed: () => Navigator.pop(
                context,
                TelevisionPlaybackSetting(preload: !preload),
              ),
            ),
            const SizedBox(height: 8),
            Text(preloadStatus, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 20),
            RemoteButton(
              label: favorite ? '取消追剧' : '加入追剧',
              icon: favorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              onPressed: () {
                onFavorite();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('返回播放'),
      ),
    ],
  );
}
