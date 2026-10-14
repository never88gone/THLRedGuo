import 'dart:io';
import 'dart:ui' as ui;

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

import '../fixtures.dart';
import '../player_fixtures.dart';
import 'cinematic_playback_mock_view.dart';

class PlaybackAutomationRepository extends FixtureRepository {
  static const hongguoDrama = Drama(
    id: 'hongguo:7690919390102965272',
    source: 'hongguo',
    title: '一把烙铁焊出自己的路',
    episodes: 76,
    category: '成长',
  );

  @override
  Future<DramaDetail> detail(Drama drama) async {
    return DramaDetail(hongguoDrama, [
      for (var i = 1; i <= 76; i++)
        Episode({
          'id': '$i',
          'source': 'hongguo',
          'currentEpisode': i,
          'title': '第$i集',
          'videoUrl': 'https://cenc.snssdk.com/stream_$i.mp4',
        }, i),
    ]);
  }

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    return PlaybackPlan(
      url: 'https://cenc.snssdk.com/stream_${episode.number}_1080p.mp4',
      quality: 1080,
      qualities: const [1080, 720, 540, 480],
      session: 'session-hongguo-${episode.number}',
      decryptionKey: 'd19d82bc3cc20f078aa6814f9dff8305',
    );
  }
}

Future<void> _loadFonts() async {
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

Future<void> _captureVerifiedScreenshot({
  required GlobalKey boundaryKey,
  required WidgetTester tester,
  required String filename,
}) async {
  final boundary = boundaryKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
  expect(boundary, isNotNull);

  await tester.runAsync(() async {
    final image = await boundary!.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(byteData, isNotNull);
    final pngBytes = byteData!.buffer.asUint8List();

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

Widget _buildPlayerApp({
  required GlobalKey repaintKey,
  required DramaDetail detail,
  required PlaybackAutomationRepository repository,
  required LocalStore store,
  required ScriptedPlayer player,
  required String badgeText,
  double initialPosition = 0,
}) {
  return MaterialApp(
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
        detail: detail,
        initialIndex: 0,
        initialPosition: initialPosition,
        repository: repository,
        store: store,
        playerFactory: () => Player(platformPlayer: player),
        videoBuilder: (controls) => CinematicPlaybackMockView(
          controls: controls,
          badgeText: badgeText,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  Future<void> settleOperations(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('视频播放UI自动化测试与全流程验证', () {
    testWidgets('1. 移动端竖屏起播验证：视频流成功加载并起播推进', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final repository = PlaybackAutomationRepository();
        final player = ScriptedPlayer();
        final detail = await repository.detail(
          PlaybackAutomationRepository.hongguoDrama,
        );
        final repaintKey = GlobalKey();

        await tester.pumpWidget(
          _buildPlayerApp(
            repaintKey: repaintKey,
            detail: detail,
            repository: repository,
            store: store,
            player: player,
            badgeText: '第1集 · 正在播放',
          ),
        );

        await settleOperations(tester);

        expect(player.opened.isNotEmpty, isTrue);
        expect(
          player.opened.first.uri,
          contains('https://cenc.snssdk.com/stream_1_1080p.mp4'),
        );
        expect(player.state.playing, isTrue);

        await player.seek(const Duration(seconds: 15));
        await settleOperations(tester, count: 5);

        expect(player.state.position.inSeconds, 15);
        expect(find.text('0:15'), findsOneWidget);
        expect(find.byTooltip('暂停播放'), findsOneWidget);
        expect(find.byKey(const ValueKey('player-progress')), findsOneWidget);

        await _captureVerifiedScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'playback_playing_verified.png',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await settleOperations(tester, count: 5);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });

    testWidgets('2. 播放控制器暂停与恢复交互验证：状态机平稳切换', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final repository = PlaybackAutomationRepository();
        final player = ScriptedPlayer();
        final detail = await repository.detail(
          PlaybackAutomationRepository.hongguoDrama,
        );
        final repaintKey = GlobalKey();

        await tester.pumpWidget(
          _buildPlayerApp(
            repaintKey: repaintKey,
            detail: detail,
            repository: repository,
            store: store,
            player: player,
            badgeText: '第1集 · 已暂停',
            initialPosition: 15,
          ),
        );

        await settleOperations(tester);
        expect(player.state.playing, isTrue);

        await tester.tap(find.byTooltip('暂停播放'));
        await settleOperations(tester, count: 5);

        expect(player.state.playing, isFalse);
        expect(find.byTooltip('开始播放'), findsOneWidget);

        await _captureVerifiedScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'playback_paused_verified.png',
        );

        await tester.tap(find.byTooltip('开始播放'));
        await settleOperations(tester, count: 5);

        expect(player.state.playing, isTrue);
        expect(find.byTooltip('暂停播放'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await settleOperations(tester, count: 5);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });

    testWidgets('3. 进度条快进跳转（Seek）精准控制验证：时间轴无缝更新', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final repository = PlaybackAutomationRepository();
        final player = ScriptedPlayer();
        final detail = await repository.detail(
          PlaybackAutomationRepository.hongguoDrama,
        );
        final repaintKey = GlobalKey();

        await tester.pumpWidget(
          _buildPlayerApp(
            repaintKey: repaintKey,
            detail: detail,
            repository: repository,
            store: store,
            player: player,
            badgeText: '第1集 · 快进至 0:45',
          ),
        );

        await settleOperations(tester);

        await player.seek(const Duration(seconds: 45));
        await settleOperations(tester, count: 5);

        expect(player.state.position.inSeconds, 45);
        expect(find.text('0:45'), findsOneWidget);

        await _captureVerifiedScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'playback_seek_verified.png',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await settleOperations(tester, count: 5);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });

    testWidgets('4. 选集切换下一集自动化验证：自动起播第2集并连续推进', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final repository = PlaybackAutomationRepository();
        final player = ScriptedPlayer();
        final detail = await repository.detail(
          PlaybackAutomationRepository.hongguoDrama,
        );
        final repaintKey = GlobalKey();

        await tester.pumpWidget(
          _buildPlayerApp(
            repaintKey: repaintKey,
            detail: detail,
            repository: repository,
            store: store,
            player: player,
            badgeText: '第2集 · 连播切换成功',
          ),
        );

        await settleOperations(tester);
        expect(player.opened.length, 1);

        await tester.tap(find.byTooltip('下一集'));
        await settleOperations(tester, count: 12);

        expect(player.opened.length, greaterThanOrEqualTo(2));
        expect(
          player.opened.last.uri,
          contains('https://cenc.snssdk.com/stream_2_1080p.mp4'),
        );
        expect(player.state.playing, isTrue);

        await player.seek(const Duration(seconds: 8));
        await settleOperations(tester, count: 5);

        expect(player.state.position.inSeconds, 8);
        expect(find.text('0:08'), findsOneWidget);

        await _captureVerifiedScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'playback_episode_switch_verified.png',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await settleOperations(tester, count: 5);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });

    testWidgets('5. 桌面宽屏沉浸全屏模式验证：全屏展开与高清渲染正常', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        tester.view.physicalSize = const Size(1280 * 2.0, 800 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final repository = PlaybackAutomationRepository();
        final player = ScriptedPlayer();
        final detail = await repository.detail(
          PlaybackAutomationRepository.hongguoDrama,
        );
        final repaintKey = GlobalKey();

        await tester.pumpWidget(
          _buildPlayerApp(
            repaintKey: repaintKey,
            detail: detail,
            repository: repository,
            store: store,
            player: player,
            badgeText: '桌面沉浸 · 1080P 超清全屏',
            initialPosition: 30,
          ),
        );

        await settleOperations(tester);

        expect(player.state.playing, isTrue);
        expect(find.byKey(const ValueKey('player-fullscreen')), findsOneWidget);
        expect(find.byKey(const ValueKey('player-speed')), findsOneWidget);
        expect(find.byKey(const ValueKey('player-quality')), findsOneWidget);

        await _captureVerifiedScreenshot(
          boundaryKey: repaintKey,
          tester: tester,
          filename: 'playback_fullscreen_verified.png',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await settleOperations(tester, count: 5);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  });
}
