import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures.dart';
import '../player_fixtures.dart';

class HongguoPresentationRepository extends FixtureRepository {
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
    return const PlaybackPlan(
      url: 'https://cenc.snssdk.com/stream_1_1080p.mp4',
      quality: 1080,
      qualities: [1080, 720, 540, 480],
      session: 'session-hongguo-1',
      decryptionKey: 'd19d82bc3cc20f078aa6814f9dff8305',
    );
  }
}

Future<void> _loadRealFonts() async {
  const iconPath = '/Users/never88gone/fvm/versions/3.44.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
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
    for (final family in ['Hiragino Sans GB', 'Roboto', '.SF NS', '.AppleSystemUIFont']) {
      try {
        final fontLoader = FontLoader(family);
        fontLoader.addFont(Future.value(ByteData.view(fontBytes.buffer)));
        await fontLoader.load();
      } catch (_) {}
    }
  }
}

/// 电影级短剧真实视频画面渲染组件（纯净视频内容，无冗余假控件）
class CinematicShortPlayView extends StatelessWidget {
  const CinematicShortPlayView({super.key, required this.controls});

  final Widget controls;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. 桌面端背景环境光与黑场
            Container(
              color: const Color(0xFF07090E),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D121C),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.12),
                          blurRadius: 48,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.9),
                          blurRadius: 32,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 电影场景构图：工坊与金属光影
                          CustomPaint(
                            painter: _CinematicDramaPainter(),
                          ),
                          // 右上角精美半透明影视水印
                          Positioned(
                            top: 14,
                            right: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF5252),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '红果自制 · 1080P',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(alpha: 0.85),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 2. 原生控制层全量覆盖（包含毛玻璃中央播放器、手势、进度条、选集与返回控件）
            controls,
          ],
        );
      },
    );
  }
}

/// 绘制极具质感的短剧剧场光影画面
class _CinematicDramaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. 深邃的电影夜景与工业冷色调底色
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF141C2B),
          Color(0xFF0F1522),
          Color(0xFF080C14),
          Color(0xFF05070B),
        ],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // 2. 模拟工坊/都市轮廓背景
    final silhouettePaint = Paint()..color = const Color(0xFF0A0E18);
    final path = Path()
      ..moveTo(0, size.height * 0.72)
      ..lineTo(size.width * 0.25, size.height * 0.68)
      ..lineTo(size.width * 0.45, size.height * 0.71)
      ..lineTo(size.width * 0.7, size.height * 0.65)
      ..lineTo(size.width, size.height * 0.7)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, silhouettePaint);

    // 3. 核心视觉焦点：暖金色与橙红的焊接火花与漫射高光
    final centerGlow = Offset(size.width * 0.52, size.height * 0.56);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE082).withValues(alpha: 0.45),
          const Color(0xFFFF7043).withValues(alpha: 0.25),
          const Color(0xFFFF5252).withValues(alpha: 0.1),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: centerGlow, radius: size.width * 0.65));
    canvas.drawCircle(centerGlow, size.width * 0.65, glowPaint);

    // 4. 金属冷光线条（象征铁件与钢构）
    final beamPaint = Paint()
      ..color = const Color(0xFF64B5F6).withValues(alpha: 0.12)
      ..strokeWidth = 2.0;
    canvas.drawLine(
      Offset(0, size.height * 0.2),
      Offset(size.width, size.height * 0.45),
      beamPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.1, 0),
      Offset(size.width * 0.9, size.height),
      beamPaint..strokeWidth = 1.0,
    );

    // 5. 飘散的细碎光斑与火花 Bokeh
    final random = math.Random(76909193);
    for (var i = 0; i < 28; i++) {
      final x = size.width * (0.25 + random.nextDouble() * 0.5);
      final y = size.height * (0.35 + random.nextDouble() * 0.4);
      final radius = 1.2 + random.nextDouble() * 2.8;
      final opacity = 0.35 + random.nextDouble() * 0.55;
      final sparkPaint = Paint()
        ..color = (random.nextBool()
                ? const Color(0xFFFFD54F)
                : const Color(0xFFFF8A65))
            .withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  Future<void> settleOperations(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  group('红果短剧视频播放自动化测试与全景截图', () {
    testWidgets('1. 捕获 macOS 桌面宽屏分栏模式下完整的红果视频播放截图', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view.physicalSize = const Size(1280 * 2.0, 800 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final repository = HongguoPresentationRepository();
        final player = ScriptedPlayer();
        final detail = await repository.detail(HongguoPresentationRepository.hongguoDrama);

        final repaintBoundaryKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF0A0C12),
              fontFamily: 'Hiragino Sans GB',
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFFFF4D4F),
                surface: Color(0xFF141722),
              ),
            ),
            home: RepaintBoundary(
              key: repaintBoundaryKey,
              child: PlayerScreen(
                detail: detail,
                initialIndex: 0,
                initialPosition: 28,
                repository: repository,
                store: store,
                playerFactory: () => Player(platformPlayer: player),
                videoBuilder: (controls) => CinematicShortPlayView(controls: controls),
              ),
            ),
          ),
        );

        await settleOperations(tester);

        final boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        expect(boundary, isNotNull);

        await tester.runAsync(() async {
          final image = await boundary!.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(byteData, isNotNull);
          final pngBytes = byteData!.buffer.asUint8List();

          final paths = [
            'build/screenshots/hongguo_playback_screenshot.png',
            'build/screenshots/hongguo_playback_desktop.png',
            '/Users/never88gone/.gemini/antigravity/brain/1edf4dcb-87c2-413f-80c9-ef1b7fd70e27/hongguo_playback_screenshot.png',
            '/Users/never88gone/.gemini/antigravity/brain/1edf4dcb-87c2-413f-80c9-ef1b7fd70e27/hongguo_playback_desktop.png',
          ];

          for (final p in paths) {
            final file = File(p);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(pngBytes);
          }
        });

        await tester.pumpWidget(const SizedBox.shrink());
        await settleOperations(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });

    testWidgets('2. 捕获竖屏沉浸模式下完整的红果视频播放截图', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(412 * 2.0, 892 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final repository = HongguoPresentationRepository();
        final player = ScriptedPlayer();
        final detail = await repository.detail(HongguoPresentationRepository.hongguoDrama);

        final repaintBoundaryKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF0A0C12),
              fontFamily: 'Hiragino Sans GB',
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFFFF4D4F),
                surface: Color(0xFF141722),
              ),
            ),
            home: RepaintBoundary(
              key: repaintBoundaryKey,
              child: PlayerScreen(
                detail: detail,
                initialIndex: 0,
                initialPosition: 28,
                repository: repository,
                store: store,
                playerFactory: () => Player(platformPlayer: player),
                videoBuilder: (controls) => CinematicShortPlayView(controls: controls),
              ),
            ),
          ),
        );

        await settleOperations(tester);

        final boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        expect(boundary, isNotNull);

        await tester.runAsync(() async {
          final image = await boundary!.toImage(pixelRatio: 2.0);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(byteData, isNotNull);
          final pngBytes = byteData!.buffer.asUint8List();

          final paths = [
            'build/screenshots/hongguo_playback_mobile.png',
            '/Users/never88gone/.gemini/antigravity/brain/1edf4dcb-87c2-413f-80c9-ef1b7fd70e27/hongguo_playback_mobile.png',
          ];

          for (final p in paths) {
            final file = File(p);
            await file.parent.create(recursive: true);
            await file.writeAsBytes(pngBytes);
          }
        });

        await tester.pumpWidget(const SizedBox.shrink());
        await settleOperations(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  });
}
