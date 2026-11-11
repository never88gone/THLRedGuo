import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';

class _SyntheticExoVideoPlatform extends VideoPlayerPlatform {
  final events = <int, StreamController<VideoEvent>>{};
  int sequence = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++sequence;
    events[id] = StreamController<VideoEvent>();
    scheduleMicrotask(() {
      events[id]!.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 5),
          size: const Size(1280, 720),
        ),
      );
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await events[playerId]!.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolveAndroidExoCodecDiagnostics 精确解析硬件解码器与刷新率', () {
    final m7221 = resolveAndroidExoCodecDiagnostics(
      {
        'hardware': 'm7221',
        'refreshRate': 60.0,
        'hevcHardware': 'OMX.MS.HEVC.Decoder',
        'hevcSoftware': 'c2.android.hevc.decoder',
        'avcHardware': 'OMX.MS.AVC.Decoder',
        'avcSoftware': 'c2.android.avc.decoder',
      },
      PlaybackDecoderMode.hardware,
    );

    expect(
      m7221.decoder,
      'MediaCodec [m7221 · 60Hz] (HEVC:OMX.MS.HEVC.Decoder / AVC:OMX.MS.AVC.Decoder)',
    );
    expect(m7221.hwActive, isTrue);
  });

  test('resolveAndroidExoCodecDiagnostics 在仅软解设备上强制标为软解状态', () {
    final swOnly = resolveAndroidExoCodecDiagnostics(
      {
        'hardware': 'ranchu',
        'refreshRate': 60.0,
        'hevcHardware': null,
        'hevcSoftware': 'c2.android.hevc.decoder',
        'avcHardware': null,
        'avcSoftware': 'c2.android.avc.decoder',
      },
      PlaybackDecoderMode.hardware,
    );

    expect(
      swOnly.decoder,
      'MediaCodec [ranchu · 60Hz] (HEVC:c2.android.hevc.decoder(仅软解) / AVC:c2.android.avc.decoder(仅软解))',
    );
    expect(swOnly.hwActive, isFalse);

    final fallback = resolveAndroidExoCodecDiagnostics(
      null,
      PlaybackDecoderMode.hardware,
    );
    expect(fallback.decoder, 'MediaCodec');
    expect(fallback.hwActive, isTrue);
  });

  test('LunaExoPlayer.getDiagnostics 在 Android 端查询并缓存真实 MediaCodec 能力', () async {
    final previousPlatform = VideoPlayerPlatform.instance;
    final previousTarget = debugDefaultTargetPlatformOverride;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    VideoPlayerPlatform.instance = _SyntheticExoVideoPlatform();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    var channelCalls = 0;
    messenger.setMockMethodCallHandler(AppDevice.channel, (call) async {
      if (call.method == 'mediaCodecDiagnostics') {
        channelCalls++;
        return <String, dynamic>{
          'hardware': 'm7221',
          'refreshRate': 60.0,
          'hevcHardware': 'OMX.MS.HEVC.Decoder',
          'avcHardware': 'OMX.MS.AVC.Decoder',
        };
      }
      return null;
    });

    final player = LunaExoPlayer();
    try {
      await player.open(Media('/synthetic-tv-720p.mp4'), play: false);
      final first = await player.getDiagnostics(
        requestedQuality: 720,
        actualQuality: 1080,
        availableQualities: const [1080],
        mediaHost: '127.0.0.1',
      );
      final second = await player.getDiagnostics(
        requestedQuality: 720,
        actualQuality: 720,
        availableQualities: const [1080, 720],
        mediaHost: '127.0.0.1',
      );

      expect(channelCalls, 1);
      expect(first.playerEngine, 'ExoPlayer (AndroidX Media3)');
      expect(first.videoWidth, 1280);
      expect(first.videoHeight, 720);
      expect(first.isHardwareAccelerated, isTrue);
      expect(
        first.decoderName,
        'MediaCodec [m7221 · 60Hz] (HEVC:OMX.MS.HEVC.Decoder / AVC:OMX.MS.AVC.Decoder)',
      );
      expect(first.toDiaryLog(), contains('OMX.MS.HEVC.Decoder'));
      expect(second.decoderName, first.decoderName);
    } finally {
      messenger.setMockMethodCallHandler(AppDevice.channel, null);
      debugDefaultTargetPlatformOverride = previousTarget;
      VideoPlayerPlatform.instance = previousPlatform;
      await player.dispose();
    }
  });
}
