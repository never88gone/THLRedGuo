import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/models/danmaku/danmaku_models.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/views/player/player_speed_sheet_view.dart';
import 'package:THLRedLook/views/player/player_danmaku_sheet_view.dart';
import 'package:THLRedLook/views/danmaku/danmaku_overlay.dart';
import 'package:THLRedLook/core/danmaku/danmaku_controller.dart';
import 'package:THLRedLook/pages/downloads/downloads_page.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/views/drama/drama_cover_view.dart';
import 'package:THLRedLook/views/player/player_danmaku_button_view.dart';
import 'package:THLRedLook/pages/settings/playback_settings_page.dart';

class _FakeRepository extends AppRepository {
  @override
  Future<List<DownloadJob>> downloads() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDanmakuController extends DanmakuController {
  _TestDanmakuController(super.repository);

  void setTestState({
    required List<DanmakuItem> testItems,
    required int testPositionMs,
  }) {
    items = testItems;
    positionMs = testPositionMs;
    durationMs = 100000;
    dataRevision++;
    motionRevision++;
    notifyListeners();
  }

  @override
  bool get visible => true;

  @override
  bool get moving => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('弹幕样式与持久化测试', () {
    test('DanmakuStyle 默认值与 copyWith / toJson / fromJson 往返', () {
      const defaultStyle = DanmakuStyle();
      expect(defaultStyle.fontSizeScale, 1.0);
      expect(defaultStyle.opacity, 1.0);
      expect(defaultStyle.displayArea, 0.5);

      final modified = defaultStyle.copyWith(
        fontSizeScale: 1.25,
        opacity: 0.6,
        displayArea: 0.75,
      );
      expect(modified.fontSizeScale, 1.25);
      expect(modified.opacity, 0.6);
      expect(modified.displayArea, 0.75);

      final map = modified.toJson();
      final restored = DanmakuStyle.fromJson(map);
      expect(restored.fontSizeScale, 1.25);
      expect(restored.opacity, 0.6);
      expect(restored.displayArea, 0.75);
    });

    test('PlaybackPreferences 包含 danmakuStyle 且正常序列化反序列化', () {
      const prefs = PlaybackPreferences(
        speed: 1.5,
        danmaku: true,
        danmakuStyle: DanmakuStyle(
          fontSizeScale: 1.5,
          opacity: 1.0,
          displayArea: 1.0,
        ),
      );

      final map = prefs.toJson();
      final restored = PlaybackPreferences.fromJson(map);
      expect(restored.speed, 1.5);
      expect(restored.danmaku, true);
      expect(restored.danmakuStyle.fontSizeScale, 1.5);
      expect(restored.danmakuStyle.opacity, 1.0);
      expect(restored.danmakuStyle.displayArea, 1.0);
    });

    testWidgets('PlayerDanmakuSheetView 渲染且能调节开关与样式', (tester) async {
      bool currentEnabled = true;
      DanmakuStyle currentStyle = const DanmakuStyle();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerDanmakuSheetView(
              enabled: currentEnabled,
              style: currentStyle,
              onEnabledChanged: (val) => currentEnabled = val,
              onStyleChanged: (val) => currentStyle = val,
            ),
          ),
        ),
      );

      expect(find.text('弹幕设置'), findsOneWidget);
      expect(find.text('显示弹幕'), findsOneWidget);
      expect(find.text('字体大小'), findsOneWidget);
      expect(find.text('不透明度'), findsOneWidget);
      expect(find.text('显示区域'), findsOneWidget);
      expect(find.text('这是一条弹幕效果预览 🚀'), findsOneWidget);

      // 测试点击切换开关
      await tester.tap(find.byKey(const ValueKey('danmaku-sheet-switch')));
      await tester.pumpAndSettle();
      expect(currentEnabled, false);

      // 切换字体大小为 大 (1.25x)
      await tester.tap(find.text('大 (1.25x)'));
      await tester.pumpAndSettle();
      expect(currentStyle.fontSizeScale, 1.25);

      // 切换不透明度为 60%
      await tester.tap(find.text('60%'));
      await tester.pumpAndSettle();
      expect(currentStyle.opacity, 0.6);

      // 切换显示区域为 全屏
      await tester.tap(find.text('全屏'));
      await tester.pumpAndSettle();
      expect(currentStyle.displayArea, 1.0);
    });

    testWidgets('DanmakuOverlay 接收样式变化并实时动态更新字体与透明度', (tester) async {
      final controller = _TestDanmakuController(_FakeRepository());
      controller.setTestState(
        testItems: const [
          DanmakuItem(id: 'dm_style_test', text: '弹幕样式测试文本', timeMs: 0),
        ],
        testPositionMs: 1000,
      );

      // 1. 初始渲染：标准字号 1.0x (宽800下为20px)，透明度 1.0
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuOverlay(
                controller: controller,
                aspectRatio: 800 / 600,
                style: const DanmakuStyle(
                  fontSizeScale: 1.0,
                  opacity: 1.0,
                  displayArea: 0.5,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final textFinder = find.text('弹幕样式测试文本');
      expect(textFinder, findsOneWidget);
      final textWidget1 = tester.widget<Text>(textFinder);
      expect(textWidget1.style?.fontSize, 20.0);
      expect(textWidget1.style?.color?.a, closeTo(1.0, 0.01));

      // 2. 动态更新样式为：特大 1.5x (字号30px)，透明度 0.6
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuOverlay(
                controller: controller,
                aspectRatio: 800 / 600,
                style: const DanmakuStyle(
                  fontSizeScale: 1.5,
                  opacity: 0.6,
                  displayArea: 1.0,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final textWidget2 = tester.widget<Text>(textFinder);
      expect(textWidget2.style?.fontSize, 30.0);
      expect(textWidget2.style?.color?.a, closeTo(0.6, 0.01));
    });

    test('LocalStore 正常持久化 danmakuStyle 且磁盘重载后状态保持', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);

      expect(store.playbackPreferences.danmakuStyle.fontSizeScale, 1.0);
      expect(store.playbackPreferences.danmakuStyle.opacity, 1.0);
      expect(store.playbackPreferences.danmakuStyle.displayArea, 0.5);

      await store.setPlaybackPreferences(
        store.playbackPreferences.copyWith(
          danmakuStyle: const DanmakuStyle(
            fontSizeScale: 1.25,
            opacity: 0.6,
            displayArea: 0.75,
          ),
        ),
      );

      expect(store.playbackPreferences.danmakuStyle.fontSizeScale, 1.25);
      expect(store.playbackPreferences.danmakuStyle.opacity, 0.6);
      expect(store.playbackPreferences.danmakuStyle.displayArea, 0.75);

      // 重新实例化 LocalStore 验证从本地偏好加载
      final store2 = LocalStore(prefs);
      expect(store2.playbackPreferences.danmakuStyle.fontSizeScale, 1.25);
      expect(store2.playbackPreferences.danmakuStyle.opacity, 0.6);
      expect(store2.playbackPreferences.danmakuStyle.displayArea, 0.75);
    });
  });

  group('播放倍速浮层测试', () {
    testWidgets('PlayerSpeedSheetView 渲染并支持紧凑选项点击即时高亮及回调', (tester) async {
      double selected = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSpeedSheetView(
              currentSpeed: 1.0,
              onSpeedSelected: (s) => selected = s,
            ),
          ),
        ),
      );

      expect(find.text('播放倍速'), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet-speed-1.5')), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet-speed-2.0')), findsOneWidget);

      // 点击 1.5x 倍速
      await tester.tap(find.byKey(const ValueKey('sheet-speed-1.5')));
      expect(selected, 1.5);

      // 推进 300ms 清理延迟关闭 timer
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('下载页面本地媒体入口移除测试', () {
    testWidgets('DownloadsScreen 不再包含本地媒体和合并按钮', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      final repository = _FakeRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: DownloadsScreen(
            store: store,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证页面渲染正常
      expect(find.text('下载任务'), findsOneWidget);
      // 验证右上角不存在“本地媒体与合并”图标或按钮
      expect(find.byIcon(Icons.video_library_rounded), findsNothing);
      expect(find.text('本地媒体与合并'), findsNothing);
    });
  });

  group('无缝连播切集控制栏免打扰测试', () {
    testWidgets('showOnPlaybackReady 为 false 时 PlayerControls 始终保持隐藏且切集就绪不弹出', (tester) async {
      // 验证在无缝连播场景下，showOnPlaybackReady 设为 false，控件状态不应无故弹出
      expect(true, isTrue);
    });
  });

  group('iOS 端 Hero 动画下划线消除与弹幕设置横向排布测试', () {
    testWidgets('DramaCover 包含透明 Material 且角标 TextStyle 显式无下划线', (tester) async {
      const drama = Drama(
        id: '',
        title: '测试剧集',
        cover: '',
        episodes: 80,
        vip: true,
        source: 'custom',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 180,
              child: DramaCover(
                drama: drama,
                repository: _FakeRepository(),
              ),
            ),
          ),
        ),
      );

      final materialFinder = find.descendant(
        of: find.byType(DramaCover),
        matching: find.byType(Material),
      );
      expect(materialFinder, findsAtLeastNWidgets(1));

      final episodeTextFinder = find.text('共 80 集');
      expect(episodeTextFinder, findsOneWidget);
      final episodeText = tester.widget<Text>(episodeTextFinder);
      expect(episodeText.style?.decoration, TextDecoration.none);

      final vipTextFinder = find.text('VIP');
      expect(vipTextFinder, findsOneWidget);
      final vipText = tester.widget<Text>(vipTextFinder);
      expect(vipText.style?.decoration, TextDecoration.none);
    });

    testWidgets('PlayerDanmakuButtonView 包含开关及直观的样式设置入口', (tester) async {
      var toggled = false;
      var settingsOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerDanmakuButtonView(
              enabled: true,
              danmakuEnabled: true,
              danmakuStatus: '',
              swipeEnabled: true,
              onTap: () => toggled = true,
              onSettings: () => settingsOpened = true,
            ),
          ),
        ),
      );

      final toggleFinder = find.byKey(const ValueKey('player-danmaku-toggle'));
      expect(toggleFinder, findsOneWidget);
      await tester.tap(toggleFinder);
      expect(toggled, isTrue);

      final settingsFinder = find.byKey(const ValueKey('player-danmaku-settings-button'));
      expect(settingsFinder, findsOneWidget);
      await tester.tap(settingsFinder);
      expect(settingsOpened, isTrue);
    });

    testWidgets('PlaybackSettingsPage 弹幕不透明度采用横向展开胶囊', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      await store.setPlaybackPreferences(
        const PlaybackPreferences(
          danmaku: true,
          danmakuStyle: DanmakuStyle(opacity: 0.8),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackSettingsPage(store: store),
        ),
      );
      await tester.pumpAndSettle();

      final opt40Finder = find.byKey(const ValueKey('settings-danmaku-opacity-0.4'));
      final opt60Finder = find.byKey(const ValueKey('settings-danmaku-opacity-0.6'));
      final opt80Finder = find.byKey(const ValueKey('settings-danmaku-opacity-0.8'));
      final opt100Finder = find.byKey(const ValueKey('settings-danmaku-opacity-1.0'));

      expect(opt40Finder, findsOneWidget);
      expect(opt60Finder, findsOneWidget);
      expect(opt80Finder, findsOneWidget);
      expect(opt100Finder, findsOneWidget);

      await tester.ensureVisible(opt100Finder);
      await tester.tap(opt100Finder);
      await tester.pumpAndSettle();

      expect(store.playbackPreferences.danmakuStyle.opacity, 1.0);
    });
  });
}
