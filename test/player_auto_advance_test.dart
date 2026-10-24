import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/player/pip_manager.dart';
import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/player/player_menu.dart';
import 'package:THLRedLook/views/television/television_controls.dart';

class _MockAdvanceRepo extends AppRepository {
  final Map<int, String> resolvedUrls = {};
  int releaseCount = 0;

  @override
  Future<PlaybackPlan> resolve(Drama drama, Episode episode, {int quality = 0}) async {
    final url = 'https://video.mock/stream_ep_${episode.number}.mp4';
    resolvedUrls[episode.number] = url;
    return PlaybackPlan(
      url: url,
      session: 'session_${episode.number}',
    );
  }

  @override
  Future<void> release(String session) async {
    releaseCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('播放器自动连播功能与 UI 自动化测试', () {
    test('1. 验证 PlaybackPreferences 中 autoAdvance 可配置为 false 并正确持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);

      // 默认值为 true
      expect(store.playbackPreferences.autoAdvance, isTrue);

      // 关闭自动连播
      final updated = store.playbackPreferences.copyWith(autoAdvance: false);
      await store.setPlaybackPreferences(updated);

      expect(store.playbackPreferences.autoAdvance, isFalse);

      // 重新从持久化读取，确认依然为 false
      final reloadedStore = LocalStore(prefs);
      expect(reloadedStore.playbackPreferences.autoAdvance, isFalse);
    });

    testWidgets('2. UI 自动化：通用/移动端播放器设置菜单 (PlayerMenu) 渲染自动连播开关并支持点击关闭', (tester) async {
      PlaybackPreferences currentPrefs = const PlaybackPreferences(autoAdvance: true);
      PlaybackPreferences? updatedPrefs;

      // 使用 StatefulBuilder 模拟实际播放页的状态响应与重绘
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SingleChildScrollView(
                  child: PlayerMenu(
                    section: PlayerMenuSection.settings,
                    episodes: const [],
                    currentIndex: 0,
                    preferences: currentPrefs,
                    qualities: const [1080, 720, 360],
                    actualQuality: 1080,
                    local: false,
                    favorite: false,
                    mobile: true,
                    onEpisode: (_) {},
                    onFavorite: () async {},
                    onPreferences: (prefs) async {
                      updatedPrefs = prefs;
                      setState(() {
                        currentPrefs = prefs;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 验证“自动连播”开关及文案已渲染
      final autoAdvanceFinder = find.byKey(const ValueKey('player-auto-advance'));
      expect(autoAdvanceFinder, findsOneWidget);
      expect(find.text('自动连播'), findsOneWidget);
      expect(find.text('关闭后，播放结束停在当前集'), findsOneWidget);

      // 2. 检查初始状态为开启 (value == true)
      SwitchListTile switchTile = tester.widget<SwitchListTile>(autoAdvanceFinder);
      expect(switchTile.value, isTrue);

      // 3. 点击开关关闭自动连播
      await tester.tap(autoAdvanceFinder);
      await tester.pumpAndSettle();

      // 4. 验证回调触发且 autoAdvance 为 false
      expect(updatedPrefs, isNotNull);
      expect(updatedPrefs!.autoAdvance, isFalse);

      // 5. 验证 UI 控件已更新为关闭状态 (value == false)
      switchTile = tester.widget<SwitchListTile>(autoAdvanceFinder);
      expect(switchTile.value, isFalse);
    });

    testWidgets('3. UI 自动化：电视大屏端设置面板 (TelevisionSettingsDialog) 支持遥控器操作关闭自动连播', (tester) async {
      TelevisionPlaybackSetting? resultSetting;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const ValueKey('open-tv-settings'),
                  onPressed: () async {
                    resultSetting = await showDialog<TelevisionPlaybackSetting>(
                      context: context,
                      builder: (_) => TelevisionSettingsDialog(
                        speed: 1.0,
                        quality: 1080,
                        qualities: const [1080, 720, 360],
                        favorite: false,
                        onFavorite: () {},
                        autoAdvance: true, // 初始开启
                      ),
                    );
                  },
                  child: const Text('打开电视设置'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击打开电视设置弹窗
      await tester.tap(find.byKey(const ValueKey('open-tv-settings')));
      await tester.pumpAndSettle();

      // 验证电视弹窗内的自动连播遥控按钮展示“自动连播：开”
      final tvBtnFinder = find.byKey(const ValueKey('tv-auto-advance'));
      expect(tvBtnFinder, findsOneWidget);
      expect(find.text('自动连播：开'), findsOneWidget);

      // 点击该按钮关闭自动连播
      await tester.tap(tvBtnFinder);
      await tester.pumpAndSettle();

      // 验证弹窗关闭并返回了 autoAdvance: false 的设置对象
      expect(resultSetting, isNotNull);
      expect(resultSetting!.autoAdvance, isFalse);
    });

    testWidgets('4. UI 自动化：电视大屏端传入关闭状态 (autoAdvance=false) 显示为“自动连播：关”', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TelevisionSettingsDialog(
              speed: 1.0,
              quality: 1080,
              qualities: const [1080, 720, 360],
              favorite: false,
              onFavorite: () {},
              autoAdvance: false, // 传入关闭状态
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tvBtnFinder = find.byKey(const ValueKey('tv-auto-advance'));
      expect(tvBtnFinder, findsOneWidget);
      expect(find.text('自动连播：关'), findsOneWidget);
    });

    test('5. 画中画自动连播：收到 pictureInPictureEnded 时自动请求并无缝切换下一集', () async {
      const channel = MethodChannel('duanju/device');
      final nativeCalls = <MethodCall>[];
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      final repo = _MockAdvanceRepo();
      final navKey = GlobalKey<NavigatorState>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call);
        if (call.method == 'replacePictureInPictureItem') {
          return {'replaced': true};
        }
        return null;
      });

      PipManager.instance.initialize(
        navigatorKey: navKey,
        repository: repo,
        store: store,
      );

      final drama = const Drama(
        id: 'test_pip_drama',
        source: 'hongguo',
        title: '画中画连播测试剧',
        episodes: 5,
      );
      final detail = DramaDetail(
        drama,
        List.generate(
          5,
          (i) => Episode({'id': '$i', 'currentEpisode': i + 1, 'title': '第${i + 1}集'}, i + 1),
        ),
      );

      int? advancedIndex;
      PipManager.instance.registerPictureInPictureSession(
        detail: detail,
        episodeIndex: 0,
        positionMs: 1000,
        onRestoreCurrentPlayer: (_) {},
        onPictureInPictureStatusChanged: (_, _, _) {},
        onEpisodeAdvanced: (index) {
          advancedIndex = index;
        },
      );

      // 模拟进入画中画
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('pictureInPictureChanged', {'active': true}),
        ),
        (_) {},
      );

      // 原生通知当前集播完
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('pictureInPictureEnded', {'episodeIndex': 0}),
        ),
        (_) {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final replaceCall = nativeCalls.firstWhere(
        (c) => c.method == 'replacePictureInPictureItem',
        orElse: () => const MethodCall('none'),
      );
      expect(replaceCall.method, 'replacePictureInPictureItem');
      expect(replaceCall.arguments['episodeIndex'], 1);
      expect(replaceCall.arguments['url'], 'https://video.mock/stream_ep_2.mp4');
      expect(advancedIndex, 1);

      PipManager.instance.notifyPictureInPictureStopped();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('6. 画中画自动连播：当 autoAdvance=false 时，播完不触发切集', () async {
      const channel = MethodChannel('duanju/device');
      final nativeCalls = <MethodCall>[];
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      await store.setPlaybackPreferences(
        store.playbackPreferences.copyWith(autoAdvance: false),
      );
      final repo = _MockAdvanceRepo();
      final navKey = GlobalKey<NavigatorState>();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call);
        return null;
      });

      PipManager.instance.initialize(
        navigatorKey: navKey,
        repository: repo,
        store: store,
      );

      final drama = const Drama(
        id: 'test_pip_drama',
        source: 'hongguo',
        title: '画中画连播测试剧',
        episodes: 5,
      );
      final detail = DramaDetail(
        drama,
        List.generate(
          5,
          (i) => Episode({'id': '$i', 'currentEpisode': i + 1, 'title': '第${i + 1}集'}, i + 1),
        ),
      );

      int? advancedIndex;
      PipManager.instance.registerPictureInPictureSession(
        detail: detail,
        episodeIndex: 0,
        positionMs: 1000,
        onRestoreCurrentPlayer: (_) {},
        onPictureInPictureStatusChanged: (_, _, _) {},
        onEpisodeAdvanced: (index) {
          advancedIndex = index;
        },
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('pictureInPictureEnded', {'episodeIndex': 0}),
        ),
        (_) {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final replaceCalls = nativeCalls.where((c) => c.method == 'replacePictureInPictureItem');
      expect(replaceCalls.isEmpty, isTrue);
      expect(advancedIndex, isNull);

      PipManager.instance.notifyPictureInPictureStopped();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });
}
