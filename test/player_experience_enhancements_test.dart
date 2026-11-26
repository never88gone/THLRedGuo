import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:THLRedLook/core/player/background_audio_service.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/pages/player/player_pip_bounds.dart';
import 'package:THLRedLook/views/feed/feed_player_overlay.dart';
import 'package:THLRedLook/views/player/episode_transition_view.dart';
import 'package:THLRedLook/views/player/player_bottom_bar_view.dart';
import 'package:THLRedLook/views/player/player_top_bar_view.dart';
import 'package:THLRedLook/views/player/player_menu.dart';
import 'package:THLRedLook/views/player/player_save_warning_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('播放器视听与系统能力优化验证', () {
    testWidgets('1. 播放器全屏控制收敛至底部操作栏且顶部栏左侧提供退出全屏', (tester) async {
      bool backToggled = false;
      bool fullscreenToggled = false;

      // 验证非全屏状态下：顶部栏无多余全屏按钮，左侧为返回按钮
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerTopBarView(
              title: '精选短剧第一季',
              fullscreen: false,
              compact: true,
              onBack: () => backToggled = true,
              onFullscreen: () => fullscreenToggled = true,
            ),
          ),
        ),
      );

      // 顶部栏不再包含多余的全屏图标按钮
      expect(find.widgetWithIcon(IconButton, Icons.fullscreen_rounded), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.fullscreen_exit_rounded), findsNothing);

      // 点击左上角返回按钮
      final backBtnFinder = find.widgetWithIcon(IconButton, Icons.arrow_back_ios_new_rounded);
      expect(backBtnFinder, findsOneWidget);
      await tester.tap(backBtnFinder);
      expect(backToggled, isTrue);

      // 验证全屏状态下：左上角返回按钮触发退出全屏
      fullscreenToggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerTopBarView(
              title: '精选短剧第一季',
              fullscreen: true,
              compact: false,
              onBack: () {},
              onFullscreen: () => fullscreenToggled = true,
            ),
          ),
        ),
      );

      expect(find.widgetWithIcon(IconButton, Icons.fullscreen_rounded), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.fullscreen_exit_rounded), findsNothing);

      final exitBackFinder = find.widgetWithIcon(IconButton, Icons.arrow_back_rounded);
      expect(exitBackFinder, findsOneWidget);
      await tester.tap(exitBackFinder);
      expect(fullscreenToggled, isTrue);

      // 验证底部操作栏常驻且唯一提供全屏控制按钮
      bool bottomFullscreenToggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerBottomBarView(
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
              fullscreen: false,
              swipeEnabled: false,
              enabled: true,
              speed: 1.0,
              qualityLabel: '自动',
              duration: 100.0,
              position: 20.0,
              buffered: 40.0,
              seekValue: null,
              onSpeed: () {},
              onQuality: () {},
              onFullscreen: () => bottomFullscreenToggled = true,
              onSeekStart: (_) {},
              onSeekChange: (_) {},
              onSeekEnd: (_) {},
            ),
          ),
        ),
      );

      final bottomFullscreenBtn = find.byKey(const ValueKey('player-fullscreen'));
      expect(bottomFullscreenBtn, findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
      await tester.tap(bottomFullscreenBtn);
      expect(bottomFullscreenToggled, isTrue);
    });

    testWidgets('2. 底部操作栏向下滑动手势收起与后台听剧模式按钮验证', (tester) async {
      bool dismissed = false;
      bool audioToggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerBottomBarView(
              constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
              fullscreen: false,
              swipeEnabled: true,
              enabled: true,
              speed: 1.0,
              qualityLabel: '自动',
              duration: 100.0,
              position: 20.0,
              buffered: 40.0,
              seekValue: null,
              backgroundAudio: false,
              onToggleBackgroundAudio: () => audioToggled = true,
              onDismiss: () => dismissed = true,
              onFullscreen: () {},
              onSpeed: () async {},
              onQuality: () async {},
              onSeekStart: (_) {},
              onSeekChange: (_) {},
              onSeekEnd: (_) {},
            ),
          ),
        ),
      );

      // 验证后台听剧按钮存在并可点击
      final audioBtnFinder = find.byKey(const ValueKey('player-background-audio'));
      expect(audioBtnFinder, findsOneWidget);
      await tester.tap(audioBtnFinder);
      expect(audioToggled, isTrue);

      // 在底部控制栏上执行向下滑动手势
      await tester.drag(
        audioBtnFinder,
        const Offset(0, 150),
      );
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets('3. 推荐流 Overlay 包含全屏播放按钮及联动', (tester) async {
      bool fullscreenClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedPlayerOverlay(
              title: '测试精选短剧',
              episodeText: '第 1 集 · 共 50 集',
              description: '精彩剧情介绍',
              playing: true,
              enabled: true,
              following: false,
              danmakuEnabled: true,
              position: const Duration(seconds: 10),
              duration: const Duration(seconds: 60),
              onTogglePlayback: () {},
              onSeek: (_) {},
              onFavorite: () {},
              onEpisodes: () {},
              onDetail: () {},
              onDanmaku: () {},
              onSettings: () {},
              onFullscreen: () => fullscreenClicked = true,
            ),
          ),
        ),
      );

      final feedFullscreenFinder = find.byKey(const ValueKey('feed-fullscreen'));
      expect(feedFullscreenFinder, findsOneWidget);

      await tester.tap(feedFullscreenFinder);
      expect(fullscreenClicked, isTrue);
    });

    testWidgets('4. 播放器菜单中的后台听剧模式开关呈现与联动', (tester) async {
      PlaybackPreferences? updatedPrefs;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlayerMenu(
                section: PlayerMenuSection.settings,
                episodes: const [],
                currentIndex: 0,
                preferences: const PlaybackPreferences(backgroundAudio: true),
                qualities: const [1080, 720],
                actualQuality: 1080,
                local: false,
                favorite: false,
                mobile: true,
                onEpisode: (_) {},
                preloadStatus: '就绪',
                onPreferences: (prefs) async {
                  updatedPrefs = prefs;
                },
                onFavorite: () async {},
              ),
            ),
          ),
        ),
      );

      final bgAudioSwitch = find.byKey(const ValueKey('player-background-audio-enabled'));
      expect(bgAudioSwitch, findsOneWidget);

      // 确保进入可视区域后点击切换关闭
      await tester.ensureVisible(bgAudioSwitch);
      await tester.tap(bgAudioSwitch);
      await tester.pumpAndSettle();

      expect(updatedPrefs?.backgroundAudio, isFalse);
    });

    testWidgets('5. 系列观看切集过渡组件动画驱动验证', (tester) async {
      int currentEpisode = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Column(
                  children: [
                    Expanded(
                      child: EpisodeTransitionView(
                        episodeIndex: currentEpisode,
                        child: Text('当前第 $currentEpisode 集'),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => setState(() => currentEpisode++),
                      child: const Text('下一集'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('当前第 1 集'), findsOneWidget);

      // 点击切到第 2 集，触发过渡动画
      await tester.tap(find.text('下一集'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byType(SlideTransition), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.text('当前第 2 集'), findsOneWidget);
    });

    test('6. 后台听剧模式服务状态机与画中画比例安全钳位验证', () {
      // 验证画中画比例计算器在极端比例下的边界限制 (0.4184 ~ 2.39)
      final (ultraNarrowWidth, ultraNarrowHeight) =
          PlayerPipBoundsCalculator.aspectDimensions(0.1);
      final ultraNarrowRatio = ultraNarrowWidth / ultraNarrowHeight;
      expect(ultraNarrowRatio, greaterThanOrEqualTo(1 / 2.39 - 0.01));

      final (ultraWideWidth, ultraWideHeight) =
          PlayerPipBoundsCalculator.aspectDimensions(10.0);
      final ultraWideRatio = ultraWideWidth / ultraWideHeight;
      expect(ultraWideRatio, lessThanOrEqualTo(2.39 + 0.01));

      // 验证 BackgroundAudioService 单例与通知动作处理
      bool toggleCalled = false;
      bool prevCalled = false;
      bool nextCalled = false;

      BackgroundAudioService.instance.registerCallbacks(
        onTogglePlayback: () => toggleCalled = true,
        onPrevious: () => prevCalled = true,
        onNext: () => nextCalled = true,
      );

      BackgroundAudioService.instance.handleNotificationAction('toggle');
      expect(toggleCalled, isTrue);

      BackgroundAudioService.instance.handleNotificationAction('prev');
      expect(prevCalled, isTrue);

      BackgroundAudioService.instance.handleNotificationAction('next');
      expect(nextCalled, isTrue);

      BackgroundAudioService.instance.unregisterCallbacks();
    });

    testWidgets('7. 播放器进度保存异常横幅呈现、重试及手动一键关闭验证', (tester) async {
      bool retryToggled = false;
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                PlayerSaveWarningBanner(
                  message: '账号观看进度尚未同步，请检查网络后重试。',
                  onRetry: () => retryToggled = true,
                  onDismiss: () => dismissed = true,
                ),
              ],
            ),
          ),
        ),
      );

      // 验证横幅展示
      expect(find.byKey(const ValueKey('player-save-warning-bar')), findsOneWidget);
      expect(find.text('账号观看进度尚未同步，请检查网络后重试。'), findsOneWidget);

      // 点击重试按钮
      final retryFinder = find.byKey(const ValueKey('player-save-warning-retry'));
      expect(retryFinder, findsOneWidget);
      await tester.tap(retryFinder);
      expect(retryToggled, isTrue);

      // 点击关闭按钮
      final dismissFinder = find.byKey(const ValueKey('player-save-warning-dismiss'));
      expect(dismissFinder, findsOneWidget);
      await tester.tap(dismissFinder);
      expect(dismissed, isTrue);
    });
  });
}
