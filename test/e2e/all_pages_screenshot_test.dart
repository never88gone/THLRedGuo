import 'dart:io';
import 'dart:ui' as ui;

import 'package:THLRedLook/app_theme.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/core_bridge.dart';
import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/downloads_screen.dart';
import 'package:THLRedLook/home_screen.dart';
import 'package:THLRedLook/local_store.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/player_screen.dart';
import 'package:THLRedLook/rankings_screen.dart';
import 'package:THLRedLook/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:THLRedLook/ranking_models.dart';
import 'package:THLRedLook/pages/privacy/privacy_lock_page.dart';
import 'package:THLRedLook/pages/privacy/privacy_settings_page.dart';
import 'package:THLRedLook/pages/privacy/privacy_vault_page.dart';
import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/utils/privacy/privacy_vault_controller.dart';
import 'package:THLRedLook/views/privacy/pattern_lock_view.dart';
import 'package:THLRedLook/views/privacy/vault_password_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_fixtures.dart';

/// 真实字体加载工具
Future<void> _loadRealFonts() async {
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

/// 截图保存工具函数
Future<void> _captureAndSave(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String fileName,
) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  expect(boundary, isNotNull);

  await tester.runAsync(() async {
    final image = await boundary!.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(byteData, isNotNull);
    final pngBytes = byteData!.buffer.asUint8List();

    final paths = [
      'build/screenshots/$fileName',
      '/Users/never88gone/.gemini/antigravity/brain/1edf4dcb-87c2-413f-80c9-ef1b7fd70e27/$fileName',
    ];

    for (final p in paths) {
      final file = File(p);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pngBytes);
    }
  });
}

/// 电影级模拟短剧播放画面
class CinematicMockPlayerView extends StatelessWidget {
  const CinematicMockPlayerView({super.key, required this.controls});
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F1420), Color(0xFF05070A)],
            ),
          ),
          child: Center(
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    center: Alignment(0.0, -0.2),
                    radius: 0.9,
                    colors: [Color(0xFF2C1E30), Color(0xFF0D1017)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF2442).withValues(alpha: 0.15),
                      blurRadius: 36,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CinematicScenePainter(),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      bottom: 40,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF2442),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '红果首发 · 4K 原画',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '一把烙铁焊出自己的路',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Text(
                            '第 1 集：青年的破局之路',
                            style: TextStyle(
                              color: Color(0xFFD0D5DD),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        controls,
      ],
    );
  }
}

class _CinematicScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x33FF2442), Color(0x11000000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawCircle(
      Offset(size.width * 0.45, size.height * 0.35),
      size.width * 0.35,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 仿真数据仓库
class PresentationRepository extends AppRepository {
  static const hongguoDrama = Drama(
    id: 'hongguo:7690919390102965272',
    source: 'hongguo',
    title: '一把烙铁焊出自己的路',
    episodes: 76,
    category: '成长',
    description: '年轻电焊工凭借精湛技艺与不屈精神，在工业浪潮中突破重围、逆袭成长的热血励志传奇。',
    heat: '98.6万',
  );

  static const dramaList = [
    hongguoDrama,
    Drama(
      id: 'hongguo:700101',
      source: 'hongguo',
      title: '龙王出狱，天下震惊',
      episodes: 95,
      category: '战神',
      vip: true,
    ),
    Drama(
      id: 'hongguo:700102',
      source: 'hongguo',
      title: '顾总的私宠甜妻',
      episodes: 80,
      category: '甜宠',
    ),
    Drama(
      id: 'hongguo:700103',
      source: 'hongguo',
      title: '重回1990当首富',
      episodes: 68,
      category: '逆袭',
    ),
    Drama(
      id: 'hongguo:700104',
      source: 'hongguo',
      title: '狂飙之巅峰霸主',
      episodes: 102,
      category: '商战',
      vip: true,
    ),
    Drama(
      id: 'hongguo:700105',
      source: 'hongguo',
      title: '真千金她马甲又爆了',
      episodes: 85,
      category: '都市',
    ),
  ];

  @override
  Future<void> initialize() async {}

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage(dramaList);

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    return CatalogPage(dramaList, page: 1, hasMore: false);
  }

  @override
  Future<List<String>> suggestions(String query) async {
    return ['神医', '战神归来', '逆袭首富', '甜宠娇妻'];
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    return DramaDetail(drama, [
      for (var i = 1; i <= 76; i++)
        Episode({
          'id': '$i',
          'source': drama.source,
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
    );
  }

  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async => current;

  @override
  Future<void> cancelPlayback() async {}

  @override
  Future<void> release(String session) async {}

  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';

  @override
  bool get supportsDownloads => true;
  @override
  bool get supportsSourceManagement => true;

  @override
  Future<List<RankingBoard>> rankingBoards() async => const [
    RankingBoard(
      id: 'hongguo-hot',
      source: 'hongguo',
      name: '红果热播榜',
      description: '全网实时热播',
    ),
    RankingBoard(
      id: 'hongguo-real',
      source: 'hongguo',
      name: '短剧飙升榜',
      description: '人气飞速增长',
    ),
  ];

  @override
  Future<RankingPage> rankings(
    String board, {
    int page = 1,
    bool force = false,
  }) async =>
      RankingPage(
        items: [
          RankingItem(1, dramaList[0], metric: '热度 98.6万'),
          RankingItem(2, dramaList[1], metric: '热度 92.1万'),
          RankingItem(3, dramaList[2], metric: '热度 88.4万'),
          RankingItem(4, dramaList[3], metric: '热度 76.5万'),
          RankingItem(5, dramaList[4], metric: '热度 69.2万'),
          RankingItem(6, dramaList[5], metric: '热度 62.0万'),
        ],
        page: 1,
        hasMore: false,
        updatedText: '刚刚更新',
      );

  @override
  Future<List<DownloadJob>> downloads() async => [
    DownloadJob(
      id: 'job-1',
      drama: dramaList[0],
      episode: Episode(const {
        'id': '1',
        'currentEpisode': 1,
        'title': '第1集',
      }, 1),
      state: 'completed',
      bytes: 28450123,
      total: 28450123,
      progress: 1.0,
      quality: 1080,
      actualQuality: 1080,
    ),
    DownloadJob(
      id: 'job-2',
      drama: dramaList[0],
      episode: Episode(const {
        'id': '2',
        'currentEpisode': 2,
        'title': '第2集',
      }, 2),
      state: 'downloading',
      bytes: 18450123,
      total: 29500000,
      progress: 0.62,
      quality: 1080,
      actualQuality: 1080,
    ),
    DownloadJob(
      id: 'job-3',
      drama: dramaList[1],
      episode: Episode(const {
        'id': '1',
        'currentEpisode': 1,
        'title': '第1集',
      }, 1),
      state: 'queued',
      bytes: 0,
      total: 31200000,
      progress: 0.0,
      quality: 720,
      actualQuality: 720,
    ),
  ];

  @override
  Future<Map<String, dynamic>> storage() async => {
    'directory': '/Users/zhenguo/Movies/DuanjuDownloads',
    'bytes': 1024 * 1024 * 480,
    'free': 1024 * 1024 * 1024 * 128,
    'files': 42,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadRealFonts();
  });

  Future<void> pumpAndSettleUi(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Widget createWrapper(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: child,
    );
  }

  group('真果·鉴 全页面 UI 高清自动化截图生成', () {
    testWidgets('1. 移动端 首页「发现」短剧库 (01_home_mobile.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: HomeScreen(repository: repository, store: store),
          ),
        ),
      );
      await pumpAndSettleUi(tester);
      await _captureAndSave(tester, key, '01_home_mobile.png');
    });

    testWidgets('2. 移动端 首页「搜索与联想」页面 (02_home_search.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();
      await store.rememberSearch('战神');
      await store.rememberSearch('甜宠');
      await store.rememberSearch('神医逆袭');

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: HomeScreen(repository: repository, store: store),
          ),
        ),
      );
      await pumpAndSettleUi(tester);

      // 点击搜索按钮打开搜索输入框
      await tester.tap(find.byKey(const ValueKey('toggle-search')));
      await pumpAndSettleUi(tester);
      await tester.enterText(find.byType(TextField), '神医');
      await pumpAndSettleUi(tester);

      await _captureAndSave(tester, key, '02_home_search.png');
    });

    testWidgets('3. 移动端 我的「追剧收藏」Tab (03_follow_mobile.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();
      await store.toggleFavorite(PresentationRepository.hongguoDrama);
      await store.toggleFavorite(PresentationRepository.dramaList[1]);

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: HomeScreen(repository: repository, store: store),
          ),
        ),
      );
      await pumpAndSettleUi(tester);

      // 切换到追剧 Tab
      await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
      await pumpAndSettleUi(tester);

      await _captureAndSave(tester, key, '03_follow_mobile.png');
    });

    testWidgets('4. 移动端「最近观看」历史 Tab (04_history_mobile.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();
      await store.saveWatch(
        WatchEntry(
          drama: PresentationRepository.hongguoDrama,
          episode: 12,
          position: 45.0,
          duration: 90.0,
          updatedAt: DateTime.now(),
        ),
      );
      await store.saveWatch(
        WatchEntry(
          drama: PresentationRepository.dramaList[2],
          episode: 5,
          position: 28.0,
          duration: 85.0,
          updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      );

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: HomeScreen(repository: repository, store: store),
          ),
        ),
      );
      await pumpAndSettleUi(tester);

      // 切换到历史 Tab
      await tester.tap(find.byKey(const ValueKey('bottom-nav-2')));
      await pumpAndSettleUi(tester);

      await _captureAndSave(tester, key, '04_history_mobile.png');
    });

    testWidgets('5. 移动端「离线下载管理」页面 (05_downloads_mobile.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: DownloadsScreen(repository: repository, store: store),
          ),
        ),
      );
      await pumpAndSettleUi(tester);
      await _captureAndSave(tester, key, '05_downloads_mobile.png');
    });

    testWidgets('6. 移动端「短剧详情与选集」页面 (06_detail_mobile.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: DetailScreen(
              drama: PresentationRepository.hongguoDrama,
              repository: repository,
              store: store,
            ),
          ),
        ),
      );
      await pumpAndSettleUi(tester);

      final expandFinder = find.text('展开');
      if (expandFinder.evaluate().isNotEmpty) {
        await tester.tap(expandFinder);
        await pumpAndSettleUi(tester);
      }

      await _captureAndSave(tester, key, '06_detail_mobile.png');
    });

    testWidgets('7. 移动端「竖屏沉浸播放器」页面 (07_player_portrait.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();
      final player = ScriptedPlayer();
      final detail = await repository.detail(PresentationRepository.hongguoDrama);

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: PlayerScreen(
              detail: detail,
              initialIndex: 0,
              initialPosition: 28,
              repository: repository,
              store: store,
              playerFactory: () => Player(platformPlayer: player),
              videoBuilder: (controls) => CinematicMockPlayerView(controls: controls),
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await pumpAndSettleUi(tester);
      await _captureAndSave(tester, key, '07_player_portrait.png');
    });

    testWidgets('8. 移动端「横屏全屏沉浸播放器」页面 (08_player_fullscreen.png)', (tester) async {
      tester.view.physicalSize = const Size(844 * 2.0, 390 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();
      final player = ScriptedPlayer();
      final detail = await repository.detail(PresentationRepository.hongguoDrama);

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: PlayerScreen(
              detail: detail,
              initialIndex: 0,
              initialPosition: 28,
              repository: repository,
              store: store,
              playerFactory: () => Player(platformPlayer: player),
              videoBuilder: (controls) => CinematicMockPlayerView(controls: controls),
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await pumpAndSettleUi(tester);
      await _captureAndSave(tester, key, '08_player_fullscreen.png');
    });

    testWidgets('9. 移动端「系统设置与备份中心」(09_settings_mobile.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({
        'privacy_mode_enabled': true,
        'privacy_gesture_salt': 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        'privacy_gesture_hash': 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: SettingsScreen(repository: repository, store: store),
          ),
        ),
      );
      await pumpAndSettleUi(tester);
      await _captureAndSave(tester, key, '09_settings_mobile.png');
    });

    testWidgets('10. 移动端「存储空间与路径迁移」页面 (10_storage_migration.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: StorageScreen(repository: repository, store: store),
          ),
        ),
      );
      await pumpAndSettleUi(tester);
      await _captureAndSave(tester, key, '10_storage_migration.png');
    });

    testWidgets('11. 移动端「短剧排行榜」页面 (11_rankings_mobile.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = PresentationRepository();

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: RankingsScreen(
              repository: repository,
              store: store,
              initialGroup: 'hongguo',
            ),
          ),
        ),
      );
      await pumpAndSettleUi(tester);
      await _captureAndSave(tester, key, '11_rankings_mobile.png');
    });

    testWidgets('12. 桌面端 macOS 宽屏分栏全景视窗 (12_desktop_overview.png)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view.physicalSize = const Size(1280 * 2.0, 800 * 2.0);
        tester.view.devicePixelRatio = 2.0;

        SharedPreferences.setMockInitialValues({});
        final store = LocalStore(await SharedPreferences.getInstance());
        final repository = PresentationRepository();
        final player = ScriptedPlayer();
        final detail = await repository.detail(PresentationRepository.hongguoDrama);

        final key = GlobalKey();
        await tester.pumpWidget(
          createWrapper(
            RepaintBoundary(
              key: key,
              child: PlayerScreen(
                detail: detail,
                initialIndex: 0,
                initialPosition: 28,
                repository: repository,
                store: store,
                playerFactory: () => Player(platformPlayer: player),
                videoBuilder: (controls) => CinematicMockPlayerView(controls: controls),
              ),
            ),
            brightness: Brightness.dark,
          ),
        );
        await pumpAndSettleUi(tester);
        await _captureAndSave(tester, key, '12_desktop_overview.png');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('13. 移动端「九宫格手势解锁遮罩」(13_privacy_lock_page.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);
      await controller.saveGesture([0, 1, 2, 5, 8]);
      controller.lock();

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: PrivacyLockPage(controller: controller),
          ),
          brightness: Brightness.dark,
        ),
      );

      final centerFinder = find.byType(PatternLockView);
      final center = tester.getCenter(centerFinder);
      final cell = 300.0 / 3;

      final gesture = await tester.startGesture(Offset(center.dx - cell, center.dy - cell));
      await gesture.moveTo(Offset(center.dx, center.dy - cell));
      await gesture.moveTo(Offset(center.dx + cell, center.dy - cell));
      await tester.pump(const Duration(milliseconds: 30));

      await _captureAndSave(tester, key, '13_privacy_lock_page.png');
      await gesture.up();
      await pumpAndSettleUi(tester);
    });

    testWidgets('14. 移动端「隐私模式与隐私库设置」(14_privacy_settings_page.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = PrivacyLockController(prefs);
      await controller.saveGesture([0, 1, 2, 5, 8]);
      final vaultController = PrivacyVaultController(prefs);
      await vaultController.setPassword('8888');
      await vaultController.addToVault(PresentationRepository.hongguoDrama);

      final repo = PresentationRepository();
      final store = LocalStore(prefs);

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: PrivacySettingsPage(
              controller: controller,
              vaultController: vaultController,
              repository: repo,
              store: store,
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await pumpAndSettleUi(tester);

      await _captureAndSave(tester, key, '14_privacy_settings_page.png');
    });

    testWidgets('15. 移动端「隐私短剧库列表」(15_privacy_vault_page.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final vaultController = PrivacyVaultController(prefs);
      await vaultController.setPassword('8888');
      await vaultController.addToVault(PresentationRepository.hongguoDrama);
      await vaultController.addToVault(
        const Drama(
          id: 'hongguo:700101',
          source: 'hongguo',
          title: '龙王出狱，天下震惊',
          episodes: 95,
          category: '战神',
          vip: true,
        ),
      );

      final repo = PresentationRepository();
      final store = LocalStore(prefs);

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: PrivacyVaultPage(
              controller: vaultController,
              repository: repo,
              store: store,
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await pumpAndSettleUi(tester);

      await _captureAndSave(tester, key, '15_privacy_vault_page.png');
    });

    testWidgets('16. 移动端「隐私短剧库密码验证弹窗」(16_vault_password_dialog.png)', (tester) async {
      tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
      tester.view.devicePixelRatio = 2.0;

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final vaultController = PrivacyVaultController(prefs);
      await vaultController.setPassword('8888');

      final key = GlobalKey();
      await tester.pumpWidget(
        createWrapper(
          RepaintBoundary(
            key: key,
            child: Scaffold(
              backgroundColor: AppColors.darkBackground,
              body: Center(
                child: VaultPasswordDialog(
                  controller: vaultController,
                ),
              ),
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await pumpAndSettleUi(tester);

      await _captureAndSave(tester, key, '16_vault_password_dialog.png');
    });
  });
}
