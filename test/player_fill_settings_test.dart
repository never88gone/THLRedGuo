import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/core/player/player_interactions.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement.dart';
import 'package:THLRedLook/core/enhancement/video_enhancement_preferences.dart';
import 'package:THLRedLook/core/danmaku/danmaku_controller.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/player/player_page.dart';
import 'package:THLRedLook/pages/settings/player_fill_settings_page.dart';
import 'package:THLRedLook/pages/settings/settings_page.dart';
import 'package:THLRedLook/pages/settings/playback_settings_page.dart';
import 'package:THLRedLook/views/player/player_viewport_view.dart';

class _MockRepo extends AppRepository {
  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    return const PlaybackPlan(
      url: 'https://mock.snssdk.com/video/mp4/test_fill.mp4',
      decryptionKey: '',
      headers: {'Referer': 'https://novelquickapp.com/'},
      session: 'mock_session_fill',
    );
  }

  @override
  Future<void> release(String session) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockPlayer extends LunaExoPlayer {
  _MockPlayer() {
    state = const PlayerState().copyWith(
      playing: true,
      position: const Duration(seconds: 10),
      duration: const Duration(minutes: 2),
      width: 1080,
      height: 1920,
    );
  }

  @override
  String get mediaUri => 'https://mock.snssdk.com/video/mp4/test_fill.mp4';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlayerFillStyle 与 PlaybackPreferences 基础能力验证', () {
    test('默认填充样式为纯黑 (black)', () {
      const prefs = PlaybackPreferences();
      expect(prefs.fillStyle, PlayerFillStyle.black);
    });

    test('支持 copyWith 修改 fillStyle', () {
      const prefs = PlaybackPreferences();
      final themePrefs = prefs.copyWith(fillStyle: PlayerFillStyle.theme);
      expect(themePrefs.fillStyle, PlayerFillStyle.theme);

      final coverPrefs = themePrefs.copyWith(fillStyle: PlayerFillStyle.cover);
      expect(coverPrefs.fillStyle, PlayerFillStyle.cover);
    });

    test('toJson 与 fromJson 正确序列化与反序列化', () {
      const prefs = PlaybackPreferences(fillStyle: PlayerFillStyle.cover);
      final json = prefs.toJson();
      expect(json['fillStyle'], 'cover');

      final restored = PlaybackPreferences.fromJson(json);
      expect(restored.fillStyle, PlayerFillStyle.cover);
    });

    test('fromJson 容错处理：未知或缺失样式安全回退为纯黑', () {
      final restored = PlaybackPreferences.fromJson({'fillStyle': 'unknown_style'});
      expect(restored.fillStyle, PlayerFillStyle.black);

      final restoredEmpty = PlaybackPreferences.fromJson({});
      expect(restoredEmpty.fillStyle, PlayerFillStyle.black);
    });

    test('LocalStore 持久化保存与读取 fillStyle', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);

      expect(store.playbackPreferences.fillStyle, PlayerFillStyle.black);

      await store.setPlaybackPreferences(
        store.playbackPreferences.copyWith(fillStyle: PlayerFillStyle.theme),
      );
      expect(store.playbackPreferences.fillStyle, PlayerFillStyle.theme);

      await store.setPlaybackPreferences(
        store.playbackPreferences.copyWith(fillStyle: PlayerFillStyle.cover),
      );
      expect(store.playbackPreferences.fillStyle, PlayerFillStyle.cover);
    });
  });

  group('设置页面与入口导航验证', () {
    testWidgets('在设置主页展示播放器填充样式入口并可点击进入', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      final repo = _MockRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            repository: repo,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final entryFinder = find.byKey(const ValueKey('settings-player-fill-entry'));
      expect(entryFinder, findsOneWidget);
      expect(find.textContaining('当前：纯黑'), findsOneWidget);

      await tester.tap(entryFinder);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerFillSettingsPage), findsOneWidget);
      expect(find.text('播放器填充样式'), findsOneWidget);
    });

    testWidgets('在播放设置中展示播放器填充样式并可点击进入', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);

      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackSettingsPage(store: store),
        ),
      );
      await tester.pumpAndSettle();

      final entryFinder = find.byKey(const ValueKey('playback-settings-fill-style-entry'));
      expect(entryFinder, findsOneWidget);

      await tester.tap(entryFinder);
      await tester.pumpAndSettle();

      expect(find.byType(PlayerFillSettingsPage), findsOneWidget);
    });
  });

  group('PlayerFillSettingsPage 选项交互与切换', () {
    testWidgets('展示 3 个填充选项并支持点击切换更新偏好', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerFillSettingsPage(store: store),
        ),
      );
      await tester.pumpAndSettle();

      // 默认选中纯黑
      expect(find.byKey(const ValueKey('fill-style-option-black')), findsOneWidget);
      expect(find.byKey(const ValueKey('fill-style-option-theme')), findsOneWidget);
      expect(find.byKey(const ValueKey('fill-style-option-cover')), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-background-black')), findsOneWidget);

      // 切换到“目前应该使用的主题色”
      final themeOption = find.byKey(const ValueKey('fill-style-option-theme'));
      await tester.ensureVisible(themeOption);
      await tester.tap(themeOption);
      await tester.pumpAndSettle();

      expect(store.playbackPreferences.fillStyle, PlayerFillStyle.theme);
      expect(find.byKey(const ValueKey('preview-background-theme')), findsOneWidget);

      // 切换到“短剧的图片”
      final coverOption = find.byKey(const ValueKey('fill-style-option-cover'));
      await tester.ensureVisible(coverOption);
      await tester.tap(coverOption);
      await tester.pumpAndSettle();

      expect(store.playbackPreferences.fillStyle, PlayerFillStyle.cover);
      expect(find.byKey(const ValueKey('preview-background-cover')), findsOneWidget);

      // 切换回“纯黑”
      final blackOption = find.byKey(const ValueKey('fill-style-option-black'));
      await tester.ensureVisible(blackOption);
      await tester.tap(blackOption);
      await tester.pumpAndSettle();

      expect(store.playbackPreferences.fillStyle, PlayerFillStyle.black);
      expect(find.byKey(const ValueKey('preview-background-black')), findsOneWidget);
    });
  });

  group('PlayerViewportView 填充背景渲染验证', () {
    testWidgets('根据不同填充样式渲染对应的背景组件', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      final repo = _MockRepo();
      final player = _MockPlayer();
      const mockDrama = Drama(
        id: 'hongguo:123',
        source: 'hongguo',
        title: '测试短剧',
        cover: '',
      );
      final detail = DramaDetail(
        mockDrama,
        [
          Episode(const {
            'url': 'https://mock.snssdk.com/video/mp4/test_fill.mp4',
            'title': '第 1 集',
          }, 1),
        ],
      );

      Widget buildViewport(PlayerFillStyle style) {
        return MaterialApp(
          home: Scaffold(
            body: PlayerViewportView(
              television: false,
              fullscreen: false,
              pictureInPictureVisible: false,
              mobile: true,
              detail: detail,
              index: 0,
              plan: null,
              loading: false,
              loadingMessage: '',
              error: null,
              localFailure: false,
              saveWarning: null,
              player: player,
              playbackRequested: true,
              videoController: null,
              danmaku: DanmakuController(repo),
              danmakuEnabled: true,
              aspectRatio: 9 / 16,
              interactions: PlayerInteractions(
                player: player,
                available: () => true,
                baseSpeed: () => 1.0,
                onTogglePlayback: () {},
                onFullscreen: () {},
                onEpisode: (_) => '',
              ),
              enhancement: VideoEnhancementController(
                player: player,
                video: null,
                preferences: const VideoEnhancementPreferences(),
                category: '',
                tags: const [],
              ),
              enhancementForUi: null,
              speed: 1.0,
              qualityLabel: '1080P',
              showControlsOnPlaybackReady: false,
              panelOpen: false,
              canUsePictureInPicture: false,
              playerFocus: FocusNode(),
              videoPaneKey: const ValueKey('video-pane'),
              allowOnlineFallback: true,
              localOnly: false,
              isMediaIdNull: false,
              repository: repo,
              store: store,
              fillStyle: style,
              onTogglePlayback: () {},
              onSeek: (_) {},
              onSeekTo: (_) async {},
              onPlay: (_) async {},
              onRotate: () {},
              onBack: () {},
              onRetry: () async {},
              onSwitchOnline: () async {},
              onSaveProgress: () async {},
              onOpenPanel: (_) async {},
              onToggleDanmaku: () async {},
              onRetryDanmaku: () async {},
              onPushToDevice: () async {},
              onEnterPictureInPicture: () async {},
              onTelevisionEpisodes: (_) async {},
              onTelevisionSettings: (_) async {},
            ),
          ),
        );
      }

      // 1. 纯黑
      await tester.pumpWidget(buildViewport(PlayerFillStyle.black));
      await tester.pump();
      expect(find.byKey(const ValueKey('player-fill-background-black')), findsOneWidget);

      // 2. 主题色
      await tester.pumpWidget(buildViewport(PlayerFillStyle.theme));
      await tester.pump();
      expect(find.byKey(const ValueKey('player-fill-background-theme')), findsOneWidget);

      // 3. 短剧海报
      await tester.pumpWidget(buildViewport(PlayerFillStyle.cover));
      await tester.pump();
      expect(find.byKey(const ValueKey('player-fill-background-cover')), findsOneWidget);
    });

    testWidgets('播放器页面 (PlayerScreen) 在设置不同 fillStyle 时自动生效对应背景', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      final repo = _MockRepo();
      final player = _MockPlayer();
      const mockDrama = Drama(
        id: 'hongguo:play_screen_test',
        source: 'hongguo',
        title: '播放器背景联动测试',
        cover: '',
      );
      final detail = DramaDetail(
        mockDrama,
        [
          Episode(const {
            'url': 'https://mock.snssdk.com/video/mp4/test_fill.mp4',
            'title': '第 1 集',
          }, 1),
        ],
      );

      // 先设置为主题色
      await store.setPlaybackPreferences(
        store.playbackPreferences.copyWith(fillStyle: PlayerFillStyle.theme),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            detail: detail,
            initialIndex: 0,
            repository: repo,
            store: store,
            playerFactory: () => player,
            videoBuilder: (controls) => Stack(children: [controls]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('player-fill-background-theme')), findsOneWidget);
    });
  });
}
