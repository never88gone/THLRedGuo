import 'dart:async';
import 'dart:io';

import 'package:THLRedLook/core_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;

import 'real_network_helpers.dart';

void main() {
  late NativeRepository repository;
  final playerLogger = PlayerStateLogger();

  setUpAll(() async {
    repository = await RealNetworkFixture.setup();
  });

  tearDownAll(() async {
    final logPath = path.join(
      Directory.current.path,
      '.agents/teamwork/worker_m3/player_state_flow.log',
    );
    await playerLogger.saveToFile(logPath);
    print('【播放日志】已将播放器全状态流转日志持久化保存至: $logPath');
  });

  group('红果真实流媒体播放器起播实证 (Real Online Media Playback Verification)', () {
    test('驱动桌面端 media_kit / libmpv 完成真实流拉取、CENC解密、起播与进度渲染', () async {
      playerLogger.log('Step 1: 开始向红果源站请求短剧目录');
      final catalog = await repository.catalog('hongguo', page: 1);
      expect(catalog.items, isNotEmpty, reason: '红果目录拉取结果不得为空');

      final drama = catalog.items.firstWhere(
        (d) => d.episodes >= 5,
        orElse: () => catalog.items.first,
      );
      playerLogger.log('Step 2: 命中剧目', details: {
        'id': drama.id,
        'title': drama.title,
        'episodes': drama.episodes,
        'category': drama.category,
      });

      playerLogger.log('Step 3: 请求剧集详情与分集数据');
      final detail = await repository.detail(drama);
      expect(detail.episodes, isNotEmpty, reason: '剧集分集不得为空');
      final episode = detail.episodes.first;

      playerLogger.log('Step 4: 请求分集流媒体播放方案 (PlaybackPlan)', details: {
        'episodeNumber': episode.number,
        'episodeId': episode.id,
      });
      final plan = await repository.resolve(drama, episode);
      expect(plan.url, isNotEmpty);
      expect(plan.session, isNotEmpty);

      playerLogger.log('Step 5: 解析到真实 PlaybackPlan', details: {
        'url': plan.url,
        'hasDecryptionKey': plan.decryptionKey.isNotEmpty,
        'decryptionKeyHex': plan.decryptionKey,
        'quality': plan.quality,
        'qualities': plan.qualities,
        'session': plan.session,
        'headers': plan.headers,
      });

      playerLogger.log('Step 6: 创建 media_kit Player 实例并配置解密与流协议');
      final player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
          logLevel: MPVLogLevel.error,
        ),
      );

      // 配置底层 libmpv 属性
      if (player.platform is NativePlayer) {
        final platform = player.platform as NativePlayer;
        await platform.setProperty('hwdec', 'auto-safe');
        await platform.setProperty('hwdec-codecs', 'all');
        await platform.setProperty(
          'demuxer-lavf-o',
          [
            'seg_max_retry=3',
            'strict=experimental',
            'allowed_extensions=ALL',
            'protocol_whitelist=[http,https,tcp,tls,crypto,data,file]',
            if (plan.decryptionKey.isNotEmpty)
              'decryption_key=${plan.decryptionKey}',
          ].join(','),
        );
        await platform.setProperty('network-timeout', '20');
        playerLogger.log('Step 7: 成功向 libmpv 注入 demuxer-lavf-o 解密配置与硬件加速');
      }

      final bufferingEvents = <bool>[];
      final playingEvents = <bool>[];
      final durationEvents = <Duration>[];
      final positionEvents = <Duration>[];
      final videoParamsEvents = <VideoParams>[];
      final errorEvents = <String>[];

      final subscriptions = [
        player.stream.buffering.listen((b) {
          bufferingEvents.add(b);
          playerLogger.log('BufferingStateChanged', details: {'buffering': b});
        }),
        player.stream.playing.listen((p) {
          playingEvents.add(p);
          playerLogger.log('PlayingStateChanged', details: {'playing': p});
        }),
        player.stream.duration.listen((d) {
          if (d > Duration.zero) {
            durationEvents.add(d);
            playerLogger.log('DurationUpdated', details: {
              'durationMs': d.inMilliseconds,
              'durationFormatted': d.toString(),
            });
          }
        }),
        player.stream.position.listen((pos) {
          if (pos > Duration.zero) {
            positionEvents.add(pos);
            playerLogger.log('PositionProgress', details: {
              'positionMs': pos.inMilliseconds,
              'positionSeconds': (pos.inMilliseconds / 1000.0).toStringAsFixed(2),
            });
          }
        }),
        player.stream.videoParams.listen((vp) {
          if ((vp.w ?? 0) > 0) {
            videoParamsEvents.add(vp);
            playerLogger.log('VideoParamsDecoded', details: {
              'width': vp.w,
              'height': vp.h,
              'aspect': vp.aspect,
            });
          }
        }),
        player.stream.error.listen((err) {
          errorEvents.add(err);
          playerLogger.log('PlayerError', details: {'error': err});
        }),
      ];

      try {
        playerLogger.log('Step 8: 调用 player.open 打开流媒体地址');
        await player.setVolume(0); // 静音播放防止测试干扰
        await player.open(
          Media(plan.url, httpHeaders: plan.headers),
          play: true,
        );

        playerLogger.log('Step 9: 等待起播状态转换 (Buffering -> Playing, Duration > 0, Position > 0)');

        // 等待起播：时长读取到 > 0，状态为 playing，且进度推进 > 500ms
        final timer = Stopwatch()..start();
        while (timer.elapsed < const Duration(seconds: 40)) {
          final isPlaying = player.state.playing;
          final duration = player.state.duration;
          final position = player.state.position;

          if (isPlaying && duration > Duration.zero && position.inMilliseconds >= 500) {
            playerLogger.log('起播验证达成！', details: {
              'playing': isPlaying,
              'durationMs': duration.inMilliseconds,
              'positionMs': position.inMilliseconds,
              'elapsedWaitMs': timer.elapsedMilliseconds,
            });
            break;
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // 核心实证断言
        expect(errorEvents, isEmpty, reason: '流媒体播放过程不得产生未处理的播放错误: $errorEvents');
        expect(player.state.playing, isTrue, reason: '播放器状态必须处于 playing');
        expect(player.state.duration, greaterThan(Duration.zero),
            reason: '播放器必须读取到大于 0 的真实总时长');
        expect(player.state.position.inMilliseconds, greaterThanOrEqualTo(500),
            reason: '播放进度必须平稳推进 (position >= 500ms)');

        print('【起播实证成功】');
        print('  - 真实视频时长: ${player.state.duration}');
        print('  - 推进播放进度: ${player.state.position}');
        print('  - 视频解码分辨率: ${player.state.width} x ${player.state.height}');

        // 步骤 10: 验证暂停与恢复交互
        playerLogger.log('Step 10: 验证暂停操作');
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 400));
        expect(player.state.playing, isFalse, reason: '暂停后 playing 必须为 false');
        final pausedPosition = player.state.position;

        playerLogger.log('Step 11: 验证 Seek 快进交互');
        await player.seek(const Duration(seconds: 3));
        await Future.delayed(const Duration(milliseconds: 600));
        expect(player.state.position.inSeconds, greaterThanOrEqualTo(2),
            reason: '快进跳转后 position 必须推进至相应时间');

        playerLogger.log('Step 12: 验证继续播放');
        await player.play();
        await Future.delayed(const Duration(seconds: 1));
        expect(player.state.playing, isTrue, reason: '恢复播放后 playing 必须为 true');
        expect(player.state.position, greaterThan(pausedPosition),
            reason: '恢复播放后进度必须继续增加');

        playerLogger.log('Step 13: 播放测试全部达成，正常释放资源');
      } finally {
        for (final s in subscriptions) {
          await s.cancel();
        }
        await player.dispose();
        await repository.release(plan.session);
        playerLogger.log('Step 14: 播放器与原生会话已成功销毁');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
