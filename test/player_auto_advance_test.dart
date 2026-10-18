import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/views/player/player_menu.dart';
import 'package:THLRedLook/views/television/television_controls.dart';

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
  });
}
