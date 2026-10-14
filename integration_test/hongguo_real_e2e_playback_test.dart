import 'dart:io';

import 'package:THLRedLook/core_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;

import '../test/real_network/real_network_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late NativeRepository repository;
  final recorder = NetworkTraceRecorder();
  final playerLogger = PlayerStateLogger();

  setUpAll(() async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });

    MacOSFrameworkLoader.ensureFrameworksLoaded();

    repository = NativeRepository();
    await repository.initialize();
  });

  tearDownAll(() async {
    final tracePath = path.join(
      Directory.current.path,
      '.agents/teamwork/worker_m3/hongguo_network_trace.json',
    );
    await recorder.saveToFile(tracePath);

    final logPath = path.join(
      Directory.current.path,
      '.agents/teamwork/worker_m3/player_state_flow.log',
    );
    await playerLogger.saveToFile(logPath);
  });

  group('红果真实端到端网络与播放集成测试 (Hongguo Real E2E Playback)', () {
    testWidgets('端到端闭环: 分类浏览 -> 搜索联想 -> 详情连续性 -> CENC解密起播 -> 进度平稳推进', (tester) async {
      // 1. 验证原生核心
      final state = repository.runtimeState;
      expect(state, isNotNull);
      expect(state!.version, isNotEmpty);
      expect(state.standalone, isTrue);

      // 2. 分类与游标分页
      final categories = await repository.categories('hongguo');
      expect(categories, isNotEmpty);

      final page1 = await repository.catalog('hongguo', page: 1, category: 'short_play');
      expect(page1.items, isNotEmpty);
      final drama = page1.items.firstWhere(
        (d) => d.episodes >= 5,
        orElse: () => page1.items.first,
      );

      // 3. 智能搜索与联想
      final suggestions = await repository.suggestions('神医');
      expect(suggestions, isNotEmpty);

      // 4. 详情与分集连续性
      final detail = await repository.detail(drama);
      expect(detail.episodes, isNotEmpty);
      for (var i = 0; i < detail.episodes.length; i++) {
        expect(detail.episodes[i].number, equals(i + 1));
      }

      // 5. 解析 PlaybackPlan (含 CENC 解密密钥)
      final episode = detail.episodes.first;
      final plan = await repository.resolve(drama, episode);
      expect(plan.url, isNotEmpty);
      expect(plan.session, isNotEmpty);
      expect(plan.qualities, isNotEmpty);
      if (plan.decryptionKey.isNotEmpty) {
        expect(plan.decryptionKey.length, equals(32));
      }

      // 6. 真实播放器 media_kit / libmpv 起播
      final player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
          logLevel: MPVLogLevel.error,
        ),
      );

      if (player.platform is NativePlayer) {
        final platform = player.platform as NativePlayer;
        await platform.setProperty('hwdec', 'auto-safe');
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
      }

      try {
        await player.setVolume(0);
        await player.open(
          Media(plan.url, httpHeaders: plan.headers),
          play: true,
        );

        final timer = Stopwatch()..start();
        while (timer.elapsed < const Duration(seconds: 40)) {
          if (player.state.playing &&
              player.state.duration > Duration.zero &&
              player.state.position.inMilliseconds >= 500) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 200));
        }

        expect(player.state.playing, isTrue);
        expect(player.state.duration, greaterThan(Duration.zero));
        expect(player.state.position.inMilliseconds, greaterThanOrEqualTo(500));

        binding.reportData ??= {};
        binding.reportData!['realHongguoE2E'] = {
          'version': state.version,
          'dramaTitle': drama.title,
          'dramaId': drama.id,
          'episodes': detail.episodes.length,
          'quality': plan.quality,
          'decryptionKeyPresent': plan.decryptionKey.isNotEmpty,
          'durationMs': player.state.duration.inMilliseconds,
          'positionMs': player.state.position.inMilliseconds,
          'width': player.state.width,
          'height': player.state.height,
        };
      } finally {
        await player.dispose();
        await repository.release(plan.session);
      }
    }, timeout: const Timeout(Duration(minutes: 4)));
  });
}
