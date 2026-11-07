import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/player/luna_exo_player.dart';
import 'package:THLRedLook/core/player/pip_manager.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/player/player_page.dart';
import 'package:THLRedLook/pages/settings/playback_settings_page.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/views/player/player_bottom_bar_view.dart';

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
      url: 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4',
      decryptionKey: '',
      headers: {'Referer': 'https://novelquickapp.com/'},
      session: 'mock_session_123',
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
      position: const Duration(seconds: 45),
      duration: const Duration(minutes: 3),
      width: 1080,
      height: 1920,
    );
  }

  @override
  String get mediaUri => 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4';

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    state = state.copyWith(playing: play);
  }

  @override
  Future<void> play() async {
    state = state.copyWith(playing: true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('修改播放器倍速后保留兼容解码和关闭的画中画偏好', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      await store.setPlaybackPreferences(
        store.playbackPreferences.copyWith(
          decoderMode: PlaybackDecoderMode.compatible,
          pictureInPicture: false,
          preload: false,
          danmaku: false,
        ),
      );
      const drama = Drama(id: 'synthetic', source: 'hongguo', title: '合成播放器设置');
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            detail: DramaDetail(drama, [
              Episode(const {'url': 'synthetic', 'title': '第1集'}, 1),
            ]),
            initialIndex: 0,
            repository: _MockRepo(),
            store: store,
            playerFactory: _MockPlayer.new,
            videoBuilder: (controls) => Stack(children: [controls]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      tester
          .widget<PlayerBottomBarView>(find.byType(PlayerBottomBarView).first)
          .onSpeed();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sheet-speed-1.5')));
      await tester.pumpAndSettle();
      expect(store.playbackPreferences.speed, 1.5);
      expect(
        store.playbackPreferences.decoderMode,
        PlaybackDecoderMode.compatible,
      );
      expect(store.playbackPreferences.pictureInPicture, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('画中画 (Picture-in-Picture) 设置与播放器联动测试', () {
    test(
      '1. 验证 PlaybackPreferences 中 pictureInPicture 默认为 true，并支持 copyWith 与持久化序列化',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = LocalStore(prefs);

        expect(store.playbackPreferences.pictureInPicture, isTrue);

        final updated = store.playbackPreferences.copyWith(
          pictureInPicture: false,
        );
        await store.setPlaybackPreferences(updated);

        expect(store.playbackPreferences.pictureInPicture, isFalse);

        final reloadedStore = LocalStore(prefs);
        expect(reloadedStore.playbackPreferences.pictureInPicture, isFalse);

        final json = updated.toJson();
        expect(json['pictureInPicture'], isFalse);
        final restored = PlaybackPreferences.fromJson(json);
        expect(restored.pictureInPicture, isFalse);
      },
    );

    testWidgets(
      '2. UI 验证：PlaybackSettingsPage 在 Android/iOS 平台渲染画中画模式开关并支持点击开启',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final store = LocalStore(prefs);
          await store.setPlaybackPreferences(
            store.playbackPreferences.copyWith(pictureInPicture: false),
          );

          expect(store.playbackPreferences.pictureInPicture, isFalse);

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.light(),
              home: PlaybackSettingsPage(store: store),
            ),
          );
          await tester.pumpAndSettle();

          final switchFinder = find.byKey(
            const ValueKey('settings-pip-switch'),
          );
          expect(switchFinder, findsOneWidget);
          expect(find.text('画中画模式'), findsOneWidget);

          SwitchListTile tile = tester.widget<SwitchListTile>(switchFinder);
          expect(tile.value, isFalse);

          await tester.tap(switchFinder);
          await tester.pumpAndSettle();

          expect(store.playbackPreferences.pictureInPicture, isTrue);
          tile = tester.widget<SwitchListTile>(switchFinder);
          expect(tile.value, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('3. UI 验证：iOS 平台同样正确渲染并支持切换画中画设置', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = LocalStore(prefs);
        await store.setPlaybackPreferences(
          store.playbackPreferences.copyWith(pictureInPicture: false),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: PlaybackSettingsPage(store: store),
          ),
        );
        await tester.pumpAndSettle();

        final switchFinder = find.byKey(const ValueKey('settings-pip-switch'));
        expect(switchFinder, findsOneWidget);

        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(store.playbackPreferences.pictureInPicture, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('4. 播控联动：当画中画关闭时播放器底部栏隐藏画中画按钮；开启且可用时显示画中画按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerBottomBarView(
              constraints: const BoxConstraints(maxWidth: 800),
              fullscreen: false,
              swipeEnabled: false,
              enabled: true,
              speed: 1.0,
              qualityLabel: '1080P',
              duration: 120.0,
              position: 30.0,
              buffered: 60.0,
              seekValue: null,
              onSpeed: () {},
              onQuality: () {},
              onFullscreen: () {},
              onSeekStart: (_) {},
              onSeekChange: (_) {},
              onSeekEnd: (_) {},
              onPictureInPicture: null, // 未开启
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pipBtnFinder = find.byKey(
        const ValueKey('player-picture-in-picture'),
      );
      expect(pipBtnFinder, findsNothing);

      bool pipClicked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerBottomBarView(
              constraints: const BoxConstraints(maxWidth: 800),
              fullscreen: false,
              swipeEnabled: false,
              enabled: true,
              speed: 1.0,
              qualityLabel: '1080P',
              duration: 120.0,
              position: 30.0,
              buffered: 60.0,
              seekValue: null,
              onSpeed: () {},
              onQuality: () {},
              onFullscreen: () {},
              onSeekStart: (_) {},
              onSeekChange: (_) {},
              onSeekEnd: (_) {},
              onPictureInPicture: () => pipClicked = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(pipBtnFinder, findsOneWidget);
      await tester.tap(pipBtnFinder);
      await tester.pumpAndSettle();

      expect(pipClicked, isTrue);
    });

    testWidgets('5. UI 验证：进入画中画状态时，界面绝不呈现无操作纯黑屏，必须渲染中央操作面板与安全区返回按钮', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = LocalStore(prefs);
        await store.setPlaybackPreferences(
          store.playbackPreferences.copyWith(pictureInPicture: false),
        );
        await store.setPlaybackPreferences(
          store.playbackPreferences.copyWith(pictureInPicture: true),
        );

        final mockDrama = const Drama(
          id: 'test_pip_drama_01',
          title: '画中画防黑屏测试短剧',
          source: 'hongguo',
          sourceId: '7694896136963755032',
          cover: 'https://mock.snssdk.com/cover.png',
          episodes: 5,
        );
        final mockDetail = DramaDetail(mockDrama, [
          Episode(const {
            'url': 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4',
            'title': '第 1 集',
          }, 1),
        ]);
        final mockPlayer = _MockPlayer();
        final mockRepo = _MockRepo();

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: PlayerScreen(
              detail: mockDetail,
              initialIndex: 0,
              repository: mockRepo,
              store: store,
              playerFactory: () => mockPlayer,
              videoBuilder: (controls) => Stack(children: [controls]),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final enterMessage = const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pictureInPictureChanged', {'active': true}),
        );
        await messenger.handlePlatformMessage(
          'duanju/device',
          enterMessage,
          null,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const ValueKey('player-pip-viewport-back')),
          findsOneWidget,
        );

        expect(
          find.byIcon(Icons.picture_in_picture_alt_rounded),
          findsOneWidget,
        );
        expect(find.text('正在画中画窗口中播放'), findsOneWidget);
        expect(find.textContaining('画中画防黑屏测试短剧'), findsOneWidget);

        expect(
          find.byKey(const ValueKey('player-pip-restore-btn')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('player-pip-exit-btn')),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('5.1 UI 验证：Android 平台进入画中画状态时，播控与遮罩面板彻底隐藏，确保画中画浮窗纯净播放无遮挡', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = LocalStore(prefs);
        await store.setPlaybackPreferences(
          store.playbackPreferences.copyWith(pictureInPicture: true),
        );

        final mockDrama = const Drama(
          id: 'test_pip_drama_android',
          title: 'Android画中画纯净无遮挡测试',
          source: 'hongguo',
          sourceId: '7694896136963755032',
          cover: 'https://mock.snssdk.com/cover.png',
          episodes: 5,
        );
        final mockDetail = DramaDetail(mockDrama, [
          Episode(const {
            'url': 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4',
            'title': '第 1 集',
          }, 1),
        ]);
        final mockPlayer = _MockPlayer();
        final mockRepo = _MockRepo();

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: PlayerScreen(
              detail: mockDetail,
              initialIndex: 0,
              repository: mockRepo,
              store: store,
              playerFactory: () => mockPlayer,
              videoBuilder: (controls) => Stack(children: [controls]),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final enterMessage = const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pictureInPictureChanged', {'active': true}),
        );
        await messenger.handlePlatformMessage(
          'duanju/device',
          enterMessage,
          null,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const ValueKey('player-pip-viewport-back')),
          findsNothing,
        );
        expect(
          find.byIcon(Icons.picture_in_picture_alt_rounded),
          findsNothing,
        );
        expect(find.text('正在画中画窗口中播放'), findsNothing);
        expect(
          find.byKey(const ValueKey('player-pip-restore-btn')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('player-pip-exit-btn')),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('6. 交互验证：轻触「恢复应用内播放」按钮触发 stopPictureInPicture 退出画中画并恢复应用内播放', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = LocalStore(prefs);
        await store.setPlaybackPreferences(
          store.playbackPreferences.copyWith(pictureInPicture: false),
        );
        await store.setPlaybackPreferences(
          store.playbackPreferences.copyWith(pictureInPicture: true),
        );

        final mockDrama = const Drama(
          id: 'test_pip_drama_02',
          title: '画中画恢复测试短剧',
          source: 'hongguo',
          sourceId: '7694896136963755032',
          cover: 'https://mock.snssdk.com/cover.png',
          episodes: 5,
        );
        final mockDetail = DramaDetail(mockDrama, [
          Episode(const {
            'url': 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4',
            'title': '第 1 集',
          }, 1),
        ]);
        final mockPlayer = _MockPlayer();
        final mockRepo = _MockRepo();

        bool stopCalled = false;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          AppDevice.channel,
          (call) async {
            if (call.method == 'stopPictureInPicture') {
              stopCalled = true;
              return {'stopped': true, 'position': 45000};
            }
            if (call.method == 'pictureInPictureStatus') {
              return {'supported': true, 'active': false};
            }
            return null;
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: PlayerScreen(
              detail: mockDetail,
              initialIndex: 0,
              repository: mockRepo,
              store: store,
              playerFactory: () => mockPlayer,
              videoBuilder: (controls) => Stack(children: [controls]),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final enterMessage = const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pictureInPictureChanged', {'active': true}),
        );
        await messenger.handlePlatformMessage(
          'duanju/device',
          enterMessage,
          null,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final restoreBtn = find.byKey(const ValueKey('player-pip-restore-btn'));
        expect(restoreBtn, findsOneWidget);

        await tester.tap(restoreBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(stopCalled, isTrue);
        expect(
          find.byKey(const ValueKey('player-pip-restore-btn')),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('7. 交互验证：处于画中画状态时，点击「退出播放」或左上角返回按钮可安全退出播放页，杜绝卡死', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = LocalStore(prefs);
        await store.setPlaybackPreferences(
          store.playbackPreferences.copyWith(pictureInPicture: false),
        );
        await store.setPlaybackPreferences(
          store.playbackPreferences.copyWith(pictureInPicture: true),
        );

        final mockDrama = const Drama(
          id: 'test_pip_drama_03',
          title: '画中画安全退出测试短剧',
          source: 'hongguo',
          sourceId: '7694896136963755032',
          cover: 'https://mock.snssdk.com/cover.png',
          episodes: 5,
        );
        final mockDetail = DramaDetail(mockDrama, [
          Episode(const {
            'url': 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4',
            'title': '第 1 集',
          }, 1),
        ]);
        final mockPlayer = _MockPlayer();
        final mockRepo = _MockRepo();

        final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navKey,
            theme: ThemeData.dark(),
            home: const Scaffold(body: Text('MAIN_FEED_PAGE')),
          ),
        );
        await tester.pumpAndSettle();

        navKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (context) => PlayerScreen(
              detail: mockDetail,
              initialIndex: 0,
              repository: mockRepo,
              store: store,
              playerFactory: () => mockPlayer,
              videoBuilder: (controls) => Stack(children: [controls]),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final enterMessage = const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pictureInPictureChanged', {'active': true}),
        );
        await messenger.handlePlatformMessage(
          'duanju/device',
          enterMessage,
          null,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final exitBtn = find.byKey(const ValueKey('player-pip-exit-btn'));
        expect(exitBtn, findsOneWidget);
        await tester.tap(exitBtn);
        await tester.pumpAndSettle();

        expect(find.text('MAIN_FEED_PAGE'), findsOneWidget);
        expect(find.byType(PlayerScreen), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('8. 交互与反馈验证：点击画中画按钮提供即时启动反馈，按钮转换为 Loading 状态杜绝无反应', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final preferences = await SharedPreferences.getInstance();
        preferences.setString(
          'playback_preferences',
          jsonEncode({'pictureInPicture': true}),
        );
        final store = LocalStore(preferences);

        final mockDrama = const Drama(
          id: 'test_pip_drama_04',
          title: '画中画即时反馈测试短剧',
          source: 'hongguo',
          sourceId: '7694896136963755032',
          cover: 'https://mock.snssdk.com/cover.png',
          episodes: 5,
        );
        final mockDetail = DramaDetail(mockDrama, [
          Episode(const {
            'url': 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4',
            'title': '第 1 集',
          }, 1),
        ]);
        final mockPlayer = _MockPlayer();
        final mockRepo = _MockRepo();

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: PlayerScreen(
              detail: mockDetail,
              initialIndex: 0,
              repository: mockRepo,
              store: store,
              playerFactory: () => mockPlayer,
              videoBuilder: (controls) => Stack(children: [controls]),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final pipBtn = find.byKey(const ValueKey('player-picture-in-picture'));
        expect(pipBtn, findsOneWidget);

        await tester.tap(pipBtn);
        await tester.pump();

        expect(find.text('正在启动画中画...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('9. 播放器防冲突与异常自动恢复验证：进入画中画前主播放器自动暂停，异常时自动恢复播放', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final preferences = await SharedPreferences.getInstance();
        preferences.setString(
          'playback_preferences',
          jsonEncode({'pictureInPicture': true}),
        );
        final store = LocalStore(preferences);

        final mockDrama = const Drama(
          id: 'test_pip_drama_05',
          title: '画中画防冲突恢复测试',
          source: 'hongguo',
          sourceId: '7694896136963755032',
          cover: 'https://mock.snssdk.com/cover.png',
          episodes: 5,
        );
        final mockDetail = DramaDetail(mockDrama, [
          Episode(const {
            'url': 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4',
            'title': '第 1 集',
          }, 1),
        ]);
        final mockPlayer = _MockPlayer();
        final mockRepo = _MockRepo();

        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(AppDevice.channel, (call) async {
          if (call.method == 'pictureInPictureStatus') {
            return {'supported': true, 'active': false};
          }
          if (call.method == 'enterPictureInPicture') {
            return {
              'supported': true,
              'active': false,
              'requested': false,
              'error': 'The operation cannot be completed',
            };
          }
          return null;
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: PlayerScreen(
              detail: mockDetail,
              initialIndex: 0,
              repository: mockRepo,
              store: store,
              playerFactory: () => mockPlayer,
              videoBuilder: (controls) => Stack(children: [controls]),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final pipBtn = find.byKey(const ValueKey('player-picture-in-picture'));
        expect(pipBtn, findsOneWidget);
        await tester.tap(pipBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('系统画中画启动未就绪，请稍后重试'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      '10. 跨页面恢复联动验证：处于画中画状态退出播放器页面后，收到 restorePictureInPictureUI 自动重新跳转回播放器',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final preferences = await SharedPreferences.getInstance();
          preferences.setString(
            'playback_preferences',
            jsonEncode({'pictureInPicture': true}),
          );
          final store = LocalStore(preferences);
          final mockDrama = const Drama(
            id: 'test_pip_drama_10',
            title: '画中画跨页面恢复测试短剧',
            source: 'hongguo',
            sourceId: '7694896136963755032',
            cover: 'https://mock.snssdk.com/cover.png',
            episodes: 5,
          );
          final mockDetail = DramaDetail(mockDrama, [
            Episode(const {
              'url': 'https://mock.snssdk.com/video/mp4/test_pip_drama.mp4',
              'title': '第 1 集',
            }, 1),
          ]);
          final mockRepo = _MockRepo();
          final mockPlayer = _MockPlayer();
          final navigatorKey = GlobalKey<NavigatorState>();

          PipManager.instance.initialize(
            navigatorKey: navigatorKey,
            repository: mockRepo,
            store: store,
          );
          PipManager.instance.playerFactory = () => mockPlayer;
          PipManager.instance.videoBuilder = (controls) =>
              Stack(children: [controls]);

          PipManager.instance.registerPictureInPictureSession(
            detail: mockDetail,
            episodeIndex: 0,
            positionMs: 12000,
            onRestoreCurrentPlayer: (_) {},
            onPictureInPictureStatusChanged: (status, pos, speed) {},
          );
          PipManager.instance.notifyPlayerDisposed();

          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigatorKey,
              theme: ThemeData.dark(),
              home: const Scaffold(body: Text('其他主页面内容')),
            ),
          );
          await tester.pump();
          expect(find.text('其他主页面内容'), findsOneWidget);

          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          final restoreMessage = const StandardMethodCodec().encodeMethodCall(
            const MethodCall('restorePictureInPictureUI', {
              'position': 15000,
              'episodeIndex': 0,
            }),
          );
          await messenger.handlePlatformMessage(
            'duanju/device',
            restoreMessage,
            null,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(PlayerScreen), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });
}
