import 'package:THLRedLook/player_interactions.dart';
import 'package:THLRedLook/views/player/player_controls_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'player_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerInteractions Seek Gestures', () {
    late ScriptedPlayer scriptedPlayer;
    late Player player;

    setUp(() async {
      scriptedPlayer = ScriptedPlayer();
      player = Player(
        configuration: const PlayerConfiguration(),
        platformPlayer: scriptedPlayer,
      );
      await scriptedPlayer.open(Media('https://example.com/test.mp4'));
    });

    tearDown(() async {
      await player.dispose();
    });

    test('Horizontal right drag triggers seek forward and displays HUD', () async {
      Duration? soughtTarget;
      final interactions = PlayerInteractions(
        player: player,
        available: () => true,
        baseSpeed: () => 1.0,
        onTogglePlayback: () {},
        onFullscreen: () {},
        onEpisode: (_) => '',
        onSeek: (target) async {
          soughtTarget = target;
        },
      );

      // 模拟初始进度 30 秒，总时长 120 秒
      scriptedPlayer.state = scriptedPlayer.state.copyWith(
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 120),
      );

      // 手指按下屏幕中央
      interactions.pointerDown(
        const PointerDownEvent(
          pointer: 1,
          position: Offset(200, 400),
          kind: PointerDeviceKind.touch,
          buttons: kPrimaryButton,
        ),
        swipeEnabled: true,
        width: 400,
        height: 800,
      );

      // 横向向右滑动 80 像素 (水平移动)
      interactions.pointerMove(
        const PointerMoveEvent(
          pointer: 1,
          position: Offset(280, 400),
          kind: PointerDeviceKind.touch,
          buttons: kPrimaryButton,
        ),
      );

      expect(interactions.isSeekActive, isTrue);
      expect(interactions.hudState.type, equals(SwipeAction.seek));
      expect(interactions.hudState.deltaSeconds, greaterThan(0));
      expect(interactions.hudState.position.inSeconds, greaterThan(30));

      // 手指抬起
      interactions.pointerUp(
        const PointerUpEvent(
          pointer: 1,
          position: Offset(280, 400),
          kind: PointerDeviceKind.touch,
        ),
      );

      expect(soughtTarget, isNotNull);
      expect(soughtTarget!.inSeconds, greaterThan(30));

      interactions.dispose();
    });

    test('Horizontal left drag triggers seek backward and displays HUD', () async {
      Duration? soughtTarget;
      final interactions = PlayerInteractions(
        player: player,
        available: () => true,
        baseSpeed: () => 1.0,
        onTogglePlayback: () {},
        onFullscreen: () {},
        onEpisode: (_) => '',
        onSeek: (target) async {
          soughtTarget = target;
        },
      );

      // 模拟初始进度 60 秒，总时长 120 秒
      scriptedPlayer.state = scriptedPlayer.state.copyWith(
        position: const Duration(seconds: 60),
        duration: const Duration(seconds: 120),
      );

      // 手指按下屏幕中央
      interactions.pointerDown(
        const PointerDownEvent(
          pointer: 2,
          position: Offset(200, 400),
          kind: PointerDeviceKind.touch,
          buttons: kPrimaryButton,
        ),
        swipeEnabled: true,
        width: 400,
        height: 800,
      );

      // 横向向左滑动 80 像素
      interactions.pointerMove(
        const PointerMoveEvent(
          pointer: 2,
          position: Offset(120, 400),
          kind: PointerDeviceKind.touch,
          buttons: kPrimaryButton,
        ),
      );

      expect(interactions.isSeekActive, isTrue);
      expect(interactions.hudState.type, equals(SwipeAction.seek));
      expect(interactions.hudState.deltaSeconds, lessThan(0));
      expect(interactions.hudState.position.inSeconds, lessThan(60));

      // 手指抬起
      interactions.pointerUp(
        const PointerUpEvent(
          pointer: 2,
          position: Offset(120, 400),
          kind: PointerDeviceKind.touch,
        ),
      );

      expect(soughtTarget, isNotNull);
      expect(soughtTarget!.inSeconds, lessThan(60));

      interactions.dispose();
    });

    testWidgets('PlayerControls gesture surface renders seek HUD card upon horizontal drag', (tester) async {
      final interactions = PlayerInteractions(
        player: player,
        available: () => true,
        baseSpeed: () => 1.0,
        onTogglePlayback: () {},
        onFullscreen: () {},
        onEpisode: (_) => '',
      );

      scriptedPlayer.state = scriptedPlayer.state.copyWith(
        position: const Duration(seconds: 40),
        duration: const Duration(seconds: 100),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 800,
              child: PlayerControls(
                player: player,
                interactions: interactions,
                enabled: true,
                fullscreen: false,
                showOnPlaybackReady: true,
                onFullscreen: () {},
                onBack: () {},
                onPrevious: () {},
                onNext: () {},
                title: '测试剧集',
                onTogglePlayback: () {},
                onEpisodes: () async {},
                onSpeed: () async {},
                onQuality: () async {},
                speed: 1.0,
                qualityLabel: '原画',
                onFocusSurface: () {},
                swipeEnabled: true,
              ),
            ),
          ),
        ),
      );

      // 验证未滑动手势时没有 HUD
      expect(find.byKey(const ValueKey('seek-hud-card')), findsNothing);

      // 在手势区域执行横向拖拽
      final gestureSurface = find.byKey(const ValueKey('player-gesture-surface'));
      expect(gestureSurface, findsOneWidget);

      final gesture = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();

      // 验证快进卡片已成功渲染显示
      expect(find.byKey(const ValueKey('seek-hud-card')), findsOneWidget);

      // 抬起手指
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));

      interactions.dispose();
    });
  });
}
