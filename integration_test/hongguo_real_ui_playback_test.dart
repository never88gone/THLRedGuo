import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/real_network/real_network_helpers.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late NativeRepository repository;
  late Drama realDrama;
  late DramaDetail realDetail;

  setUpAll(() async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });

    MacOSFrameworkLoader.ensureFrameworksLoaded();

    repository = NativeRepository();
    await repository.initialize();

    final catalog = await repository.catalog('hongguo', page: 1);
    realDrama = catalog.items.firstWhere(
      (d) => d.episodes >= 5,
      orElse: () => catalog.items.first,
    );
    realDetail = await repository.detail(realDrama);
  });

  group('红果真实视频流与UI全流程集成起播验证', () {
    testWidgets('端到端真实UI测试：驱动真实流拉取、CENC解密、Video控件渲染与播放控制', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());

      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AppColors.darkBackground,
            colorScheme: const ColorScheme.dark(
              primary: AppColors.hongguoRed,
              surface: AppColors.darkSurface,
            ),
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: repaintKey,
              child: PlayerScreen(
                detail: realDetail,
                initialIndex: 0,
                initialPosition: 0,
                repository: repository,
                store: store,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. 查找挂载在 UI 树上的真实 Video 控件与底层的真实 Player 实例
      Player? player;
      final timer = Stopwatch()..start();
      while (timer.elapsed < const Duration(seconds: 40)) {
        await tester.pump(const Duration(milliseconds: 300));
        final videoFinder = find.byType(Video);
        if (videoFinder.evaluate().isNotEmpty) {
          final videoWidget = tester.widget<Video>(videoFinder.first);
          player = videoWidget.controller.player;
          if (player.state.playing &&
              player.state.duration > Duration.zero &&
              player.state.position.inMilliseconds >= 500) {
            break;
          }
        }
      }

      expect(player, isNotNull, reason: 'UI 必须成功实例化真实 Video 控件与 Player');
      expect(player!.state.playing, isTrue, reason: '真实流媒体在 UI 上必须进入 playing 状态');
      expect(
        player.state.duration,
        greaterThan(Duration.zero),
        reason: '播放器必须读取到真实视频时长',
      );
      expect(
        player.state.position.inMilliseconds,
        greaterThanOrEqualTo(500),
        reason: '真实视频进度必须稳定向前推进 (position >= 500ms)',
      );

      // 验证 UI 上的控制器状态（正在播放态应显示暂停按钮）
      await tester.pump();
      expect(find.byTooltip('暂停播放'), findsOneWidget);
      expect(find.byKey(const ValueKey('player-progress')), findsOneWidget);

      // 捕获真实视频画面渲染与UI界面的起播实况截图
      try {
        final boundary = repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        debugPrint('【起播实况检查】boundary=$boundary, playerPlaying=${player.state.playing}, width=${player.state.width}, height=${player.state.height}');
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 1.0);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final pngBytes = byteData.buffer.asUint8List();
            final outPath = '${Directory.systemTemp.path}/real_hongguo_playback_ui.png';
            final tmpFile = File(outPath);
            tmpFile.writeAsBytesSync(pngBytes, flush: true);
            debugPrint('【起播截图保存成功】文件路径: ${tmpFile.path}, 大小: ${pngBytes.length} 字节');
            binding.reportData ??= {};
            binding.reportData!['screenshot_playing_path'] = tmpFile.path;
          }
        }
      } catch (e, stack) {
        debugPrint('【起播截屏捕获异常】$e\n$stack');
      }

      // 2. 验证 UI 暂停交互
      await tester.tap(find.byTooltip('暂停播放'));
      final pauseTimer = Stopwatch()..start();
      while (pauseTimer.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (!player.state.playing) break;
      }
      expect(player.state.playing, isFalse, reason: '点击 UI 暂停按钮后播放器必须暂停');
      expect(find.byTooltip('开始播放'), findsOneWidget);

      // 捕获暂停状态截图
      try {
        final boundary = repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 1.0);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final pngBytes = byteData.buffer.asUint8List();
            final outPath = '${Directory.systemTemp.path}/real_hongguo_playback_paused_ui.png';
            final tmpFile = File(outPath);
            tmpFile.writeAsBytesSync(pngBytes, flush: true);
            debugPrint('【暂停截图保存成功】文件路径: ${tmpFile.path}, 大小: ${pngBytes.length} 字节');
            binding.reportData ??= {};
            binding.reportData!['screenshot_paused_path'] = tmpFile.path;
          }
        }
      } catch (e) {
        debugPrint('【暂停截屏捕获异常】$e');
      }

      final pausedPosition = player.state.position;

      // 3. 验证 UI 恢复播放交互
      await tester.tap(find.byTooltip('开始播放'));
      final resumeTimer = Stopwatch()..start();
      while (resumeTimer.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (player.state.playing && player.state.position > pausedPosition) break;
      }
      expect(player.state.playing, isTrue, reason: '点击 UI 开始播放后必须恢复起播');
      expect(player.state.position, greaterThan(pausedPosition),
          reason: '恢复播放后视频进度必须继续推进');

      // 4. 验证进度跳转 Seek 控制
      await player.seek(const Duration(seconds: 5));
      final seekTimer = Stopwatch()..start();
      while (seekTimer.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 100));
        if (player.state.position.inSeconds >= 4) break;
      }
      expect(player.state.position.inSeconds, greaterThanOrEqualTo(4),
          reason: 'Seek 跳转后视频进度必须成功同步');

      // 5. 记录并上报真实端到端集成测试指标数据
      binding.reportData ??= {};
      binding.reportData!['hongguoRealUiPlayback'] = {
        'dramaTitle': realDrama.title,
        'dramaId': realDrama.id,
        'episodes': realDetail.episodes.length,
        'durationFormatted': player.state.duration.toString(),
        'positionFormatted': player.state.position.toString(),
        'width': player.state.width,
        'height': player.state.height,
        'playing': player.state.playing,
      };

      // 优雅卸载
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
