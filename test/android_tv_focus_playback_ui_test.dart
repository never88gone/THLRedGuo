import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/television/television_controls.dart';

/// 测试专用的模拟 Player 实现，精确控制播放状态与流
class _TestPlayerStream implements PlayerStream {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get duration => _durationController.stream;

  @override
  Stream<Duration> get buffer => _bufferController.stream;

  @override
  Stream<bool> get playing => _playingController.stream;

  @override
  Stream<bool> get buffering => _bufferingController.stream;

  void dispose() {
    _positionController.close();
    _durationController.close();
    _bufferController.close();
    _playingController.close();
    _bufferingController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPlayer implements Player {
  final _stream = _TestPlayerStream();
  PlayerState _state = const PlayerState(
    playing: false,
    position: Duration(seconds: 30),
    duration: Duration(minutes: 5),
    buffer: Duration(minutes: 2),
  );

  @override
  PlayerStream get stream => _stream;

  @override
  PlayerState get state => _state;

  void updateState({
    bool? playing,
    Duration? position,
    Duration? duration,
    Duration? buffer,
    bool? buffering,
  }) {
    _state = PlayerState(
      playing: playing ?? _state.playing,
      position: position ?? _state.position,
      duration: duration ?? _state.duration,
      buffer: buffer ?? _state.buffer,
      buffering: buffering ?? _state.buffering,
    );
    if (playing != null) _stream._playingController.add(playing);
    if (position != null) _stream._positionController.add(position);
    if (duration != null) _stream._durationController.add(duration);
    if (buffer != null) _stream._bufferController.add(buffer);
    if (buffering != null) _stream._bufferingController.add(buffering);
  }

  @override
  Future<void> dispose() async {
    _stream.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildControls({
  required Player player,
  required String title,
  bool enabled = true,
  bool showOnPlaybackReady = true,
  VoidCallback? onTogglePlayback,
  ValueChanged<int>? onSeek,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  Future<void> Function()? onEpisodes,
  Future<void> Function()? onSettings,
  VoidCallback? onBack,
}) => MaterialApp(
  home: Scaffold(
    body: TelevisionControls(
      player: player,
      title: title,
      enabled: enabled,
      showOnPlaybackReady: showOnPlaybackReady,
      onTogglePlayback: onTogglePlayback ?? () {},
      onSeek: onSeek ?? (_) {},
      onPrevious: onPrevious,
      onNext: onNext,
      onEpisodes: onEpisodes ?? () async {},
      onSettings: onSettings ?? () async {},
      onBack: onBack ?? () {},
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Group 1: Android TV 遥控器核心导航与焦点流转', () {
    late _TestPlayer player;

    setUp(() => player = _TestPlayer());
    tearDown(() async => await player.dispose());

    testWidgets('1. TelevisionControls 起播就绪时，焦点自动对准播放按钮且具有焦点高亮', (tester) async {
      await tester.pumpWidget(_buildControls(
        player: player,
        title: '糖葫芦短剧 · 电视自动化测试第1集',
      ));
      await tester.pumpAndSettle();

      expect(find.text('糖葫芦短剧 · 电视自动化测试第1集'), findsOneWidget);
      final playBtnFinder = find.byKey(const ValueKey('tv-play-pause'));
      expect(playBtnFinder, findsOneWidget);

      final focusScope = FocusScope.of(tester.element(playBtnFinder));
      expect(focusScope.focusedChild?.debugLabel, equals('tv-player-play'));
    });

    testWidgets('2. 遥控器右键依次导航焦点：下一集 -> 选集 -> 播放日记 -> 播放设置', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildControls(
        player: player,
        title: '测试剧集',
        onPrevious: () {},
        onNext: () {},
      ));
      await tester.pumpAndSettle();

      final playFinder = find.byKey(const ValueKey('tv-play-pause'));
      expect(playFinder, findsOneWidget);

      final focusScope = FocusScope.of(tester.element(playFinder));
      expect(focusScope.focusedChild?.debugLabel, equals('tv-player-play'));

      // 按遥控器右键 -> 下一集 (tv-next)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final nextFocusedWidget = focusScope.focusedChild?.context?.widget;
      expect(nextFocusedWidget, isNotNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tv-next')),
          matching: find.byWidget(nextFocusedWidget!),
        ),
        findsOneWidget,
      );

      // 再次按右键 -> 选集 (tv-episodes)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusScope.focusedChild?.debugLabel, equals('tv-player-episodes'));

      // 再次按右键 -> 播放日记 (tv-diary)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusScope.focusedChild?.debugLabel, equals('tv-player-diary'));

      // 再次按右键 -> 播放设置 (tv-settings)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusScope.focusedChild?.debugLabel, equals('tv-player-settings'));
    });

    testWidgets('3. 遥控器上键从底部操作栏移动焦点至播放进度条', (tester) async {
      await tester.pumpWidget(_buildControls(player: player, title: '测试剧集'));
      await tester.pumpAndSettle();

      final playBtnFinder = find.byKey(const ValueKey('tv-play-pause'));
      final focusScope = FocusScope.of(tester.element(playBtnFinder));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focusScope.focusedChild?.debugLabel, equals('tv-player-progress'));
    });

    testWidgets('4. 界面沉浸隐藏时，按遥控器方向键或确定键自动唤醒控制栏并归位焦点', (tester) async {
      player.updateState(playing: true);

      await tester.pumpWidget(_buildControls(
        player: player,
        title: '测试剧集',
        showOnPlaybackReady: false,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tv-play-pause')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tv-play-pause')), findsOneWidget);
      final playBtnFinder = find.byKey(const ValueKey('tv-play-pause'));
      final focusScope = FocusScope.of(tester.element(playBtnFinder));
      expect(focusScope.focusedChild?.debugLabel, equals('tv-player-play'));
    });
  });

  group('Group 2: Android TV 视频播放交互与快进快退', () {
    late _TestPlayer player;

    setUp(() => player = _TestPlayer());
    tearDown(() async => await player.dispose());

    testWidgets('5. 遥控器确定键 (Select/Enter) 与空格键 (Space) 触发播放与暂停切换', (tester) async {
      var toggleCount = 0;
      await tester.pumpWidget(_buildControls(
        player: player,
        title: '测试剧集',
        onTogglePlayback: () => toggleCount++,
      ));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(toggleCount, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(toggleCount, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(toggleCount, 3);
    });

    testWidgets('6. 控制栏隐藏时按遥控器左右键直接触发 ±10 秒快进/快退并弹出 HUD', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      player.updateState(playing: true);
      var seekOffset = 0;
      await tester.pumpWidget(_buildControls(
        player: player,
        title: '测试剧集',
        showOnPlaybackReady: false,
        onSeek: (seconds) => seekOffset += seconds,
      ));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(seekOffset, 10);
      expect(find.text('0:30 / 5:00'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(seekOffset, 0);
    });

    testWidgets('7. 按遥控器返回键 (Escape) 触发 onBack 回调', (tester) async {
      var backCalled = false;
      await tester.pumpWidget(_buildControls(
        player: player,
        title: '测试剧集',
        onBack: () => backCalled = true,
      ));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(backCalled, isTrue);
    });
  });

  group('Group 3: Android TV 选集弹窗与网格遥控焦点导航', () {
    testWidgets('8. 选集弹窗弹出后初始焦点自动聚焦在当前播放集数，并支持左右移动与确定选集', (tester) async {
      final episodes = List.generate(
        30,
        (i) => Episode({'id': 'ep_${i + 1}', 'number': i + 1, 'vip': false}, i + 1),
      );

      int? selectedIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedIndex = await showDialog<int>(
                  context: context,
                  builder: (_) => TelevisionEpisodeDialog(
                    episodes: episodes,
                    currentIndex: 4, // 初始在第 5 集（索引 4）
                  ),
                );
              },
              child: const Text('打开选集'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击打开选集弹窗
      await tester.tap(find.text('打开选集'));
      await tester.pumpAndSettle();

      expect(find.text('选集 · 共 30 集'), findsOneWidget);

      // 验证第 5 集按钮处于高亮或存在
      final ep5Finder = find.byKey(const ValueKey('tv-select-episode-5'));
      expect(ep5Finder, findsOneWidget);

      // 按遥控器右键向右移动到第 6 集
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // 按遥控器确定键选择第 6 集
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      // 弹窗关闭并成功返回选择的索引 5 (第 6 集)
      expect(find.byType(TelevisionEpisodeDialog), findsNothing);
      expect(selectedIndex, equals(5));
    });
  });

  group('Group 4: Android TV 播放设置面板遥控焦点与设置切换', () {
    testWidgets('9. 播放设置弹窗打开时默认聚焦在当前倍速，支持左右切换并保存', (tester) async {
      TelevisionPlaybackSetting? selectedSetting;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedSetting = await showDialog<TelevisionPlaybackSetting>(
                  context: context,
                  builder: (_) => TelevisionSettingsDialog(
                    speed: 1.0,
                    quality: 1080,
                    qualities: const [1080, 720, 480],
                    favorite: false,
                    onFavorite: () {},
                  ),
                );
              },
              child: const Text('打开设置'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();

      expect(find.text('播放设置'), findsOneWidget);
      expect(find.text('倍速'), findsOneWidget);

      // 当前 1.0x 被选中
      final speed1Finder = find.byKey(const ValueKey('tv-speed-1.0'));
      expect(speed1Finder, findsOneWidget);

      // 遥控器向右移动到 1.25x
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // 按确定键选中并退出
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(selectedSetting, isNotNull);
      expect(selectedSetting!.speed, equals(1.25));
    });
  });
}
