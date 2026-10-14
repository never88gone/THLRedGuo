import 'dart:io';
import 'dart:ui' as ui;

import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../real_network/real_network_helpers.dart';
import 'cinematic_playback_mock_view.dart';

Future<void> _loadSystemFonts() async {
  const iconPath =
      '/Users/never88gone/fvm/versions/3.44.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(iconPath).existsSync()) {
    final iconFont = FontLoader('MaterialIcons');
    final iconBytes = File(iconPath).readAsBytesSync();
    iconFont.addFont(Future.value(ByteData.view(iconBytes.buffer)));
    await iconFont.load();
  }

  const chineseCandidates = [
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    '/System/Library/Fonts/STHeiti Medium.ttc',
  ];
  Uint8List? fontBytes;
  for (final candidate in chineseCandidates) {
    if (File(candidate).existsSync()) {
      try {
        fontBytes = File(candidate).readAsBytesSync();
        break;
      } catch (_) {}
    }
  }

  if (fontBytes != null) {
    for (final family in [
      'Hiragino Sans GB',
      'Roboto',
      '.SF NS',
      '.AppleSystemUIFont',
    ]) {
      try {
        final fontLoader = FontLoader(family);
        fontLoader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
        await fontLoader.load();
      } catch (_) {}
    }
  }
}

Future<void> _saveScreenshot({
  required GlobalKey boundaryKey,
  required WidgetTester tester,
  required String filename,
}) async {
  final boundary = boundaryKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
  if (boundary == null) return;

  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final pngBytes = byteData.buffer.asUint8List();

    final paths = [
      'build/screenshots/$filename',
      '/Users/never88gone/.gemini/antigravity/brain/1edf4dcb-87c2-413f-80c9-ef1b7fd70e27/$filename',
    ];

    for (final path in paths) {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pngBytes);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeRepository repository;
  late Drama realDrama;
  late DramaDetail realDetail;

  setUpAll(() async {
    await _loadSystemFonts();
    repository = await RealNetworkFixture.setup();
    final catalog = await repository.catalog('hongguo', page: 1);
    realDrama = catalog.items.firstWhere(
      (d) => d.episodes >= 5,
      orElse: () => catalog.items.first,
    );
    realDetail = await repository.detail(realDrama);
  });

  group('红果源站真实流媒体 UI 自动化起播与交互验证', () {
    testWidgets('真实端到端UI起播验证：拉流、CENC解密、播放推进、暂停及全屏', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());

        // 构造带解密配置的原生 Player 实例
        final player = Player(
          configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024,
            logLevel: MPVLogLevel.error,
          ),
        );

        final repaintKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: AppColors.darkBackground,
              fontFamily: 'Hiragino Sans GB',
              colorScheme: const ColorScheme.dark(
                primary: AppColors.hongguoRed,
                surface: AppColors.darkSurface,
              ),
            ),
            home: RepaintBoundary(
              key: repaintKey,
              child: PlayerScreen(
                detail: realDetail,
                initialIndex: 0,
                initialPosition: 0,
                repository: repository,
                store: store,
                playerFactory: () => player,
                videoBuilder: (controls) => CinematicPlaybackMockView(
                  controls: controls,
                  badgeText: '${realDrama.title} · 第1集 正在播放',
                ),
              ),
            ),
          ),
        );

        // 初始泵出，触发 PlayerScreen initState 与 load
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 1. 等待真实流拉取、CENC 解密并进入起播推进（最多等待 30 秒）
        var playStarted = false;
        await tester.runAsync(() async {
          final stopwatch = Stopwatch()..start();
          while (stopwatch.elapsed < const Duration(seconds: 30)) {
            if (player.state.playing &&
                player.state.duration > Duration.zero &&
                player.state.position.inMilliseconds >= 500) {
              playStarted = true;
              break;
            }
            await Future.delayed(const Duration(milliseconds: 250));
          }
        });

        expect(playStarted, isTrue, reason: '真实流媒体必须在 30 秒内完成解密起播且产生播放进度');
        expect(player.state.playing, isTrue);
        expect(player.state.duration, greaterThan(Duration.zero));
        expect(player.state.position.inMilliseconds, greaterThanOrEqualTo(500));

        // 驱动 UI 渲染当前播放状态
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // 验证 UI 上的控件处于播放状态
        expect(find.byTooltip('暂停播放'), findsOneWidget);
        expect(find.byKey(const ValueKey('player-progress')), findsOneWidget);

        // 捕获真实起播实况截图
        await _saveScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'real_hongguo_playback_playing.png',
        );

        // 2. 验证 UI 暂停交互
        await tester.tap(find.byTooltip('暂停播放'));
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(player.state.playing, isFalse, reason: '点击暂停后播放器应处于暂停状态');
        expect(find.byTooltip('开始播放'), findsOneWidget);

        await _saveScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'real_hongguo_playback_paused.png',
        );

        // 3. 验证 UI 恢复播放
        await tester.tap(find.byTooltip('开始播放'));
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 600));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(player.state.playing, isTrue, reason: '点击开始播放后播放器应恢复播放');
        expect(find.byTooltip('暂停播放'), findsOneWidget);

        // 4. 验证 UI Seek 快进跳转
        await tester.runAsync(() async {
          await player.seek(const Duration(seconds: 10));
          await Future.delayed(const Duration(milliseconds: 500));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(player.state.position.inSeconds, greaterThanOrEqualTo(8));

        await _saveScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'real_hongguo_playback_seek.png',
        );

        // 5. 验证横屏全屏桌面展示
        tester.view.physicalSize = const Size(1280 * 2.0, 800 * 2.0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await _saveScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'real_hongguo_playback_fullscreen.png',
        );

        // 清理卸载
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await player.dispose();
        });
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
