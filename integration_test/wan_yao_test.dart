// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/widgets.dart';
import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/player_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS端到端UI自动化测试：搜索、播放及切季浮层验证', (WidgetTester tester) async {
    print('>>> [1/6] 启动 App 并等待首屏渲染');
    await app.main([]);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 1. 点击展开搜索栏
    print('>>> [2/6] 点击搜索图标展开搜索栏');
    final toggleSearchFinder = find.byKey(const ValueKey('toggle-search'));
    if (toggleSearchFinder.evaluate().isNotEmpty) {
      await tester.tap(toggleSearchFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // 2. 输入“万妖图录”进行搜索
    print('>>> [3/6] 输入“万妖图录”并提交搜索');
    final searchInputFinder = find.byType(TextField);
    expect(searchInputFinder, findsOneWidget);

    await tester.enterText(searchInputFinder, '万妖图录');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // 检查短剧卡片
    final dramaTileFinder = find.byType(DramaTile);
    expect(dramaTileFinder, findsWidgets, reason: '搜索结果应展示万妖图录相关卡片');
    print('>>> 搜索结果已展示，共发现 ${dramaTileFinder.evaluate().length} 个短剧卡片');

    // 3. 点击第一个短剧卡片进入详情页
    print('>>> [4/6] 点击进入短剧详情页');
    await tester.tap(dramaTileFinder.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byType(DetailScreen), findsOneWidget, reason: '应成功展示短剧详情页');
    print('>>> 详情页加载成功');

    // 4. 点击播放按钮
    print('>>> [5/6] 等待详情数据加载完成并点击播放视频');
    final playBtnFinder = find.byKey(const ValueKey('start-play'));

    // 等待详情加载完成（最多等待 15 秒）
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (playBtnFinder.evaluate().isNotEmpty && find.text('正在加载...').evaluate().isEmpty) {
        break;
      }
    }

    if (playBtnFinder.evaluate().isNotEmpty) {
      await tester.tap(playBtnFinder.first);
    } else {
      final ep1Finder = find.text('第 1 集');
      if (ep1Finder.evaluate().isNotEmpty) {
        await tester.tap(ep1Finder.first);
      } else {
        fail('未找到播放按钮或第1集按钮');
      }
    }

    // 路由跳转至 PlayerScreen，等待进入（不使用 pumpAndSettle 以免被连续视频帧重绘挂起）
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byType(PlayerScreen).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(PlayerScreen), findsOneWidget, reason: '应成功进入 PlayerScreen 播放页');

    // 观察 3 秒起播状态
    print('>>> 播放器已拉起，持续监控视频播放流与渲染...');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('无法从数据源'), findsNothing);

    // 5. 验证播放器面板中的系列多季切季交互与提示浮层快速消失
    print('>>> [6/6] 验证系列多季切换与底部提示浮层');
    // 等待系列多季异步发现完成并渲染
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.descendant(
        of: find.byType(PlayerScreen),
        matching: find.text('系列多季'),
      ).evaluate().isNotEmpty) {
        break;
      }
    }

    final seriesBarFinder = find.descendant(
      of: find.byType(PlayerScreen),
      matching: find.text('系列多季'),
    );
    if (seriesBarFinder.evaluate().isNotEmpty) {
      print('>>> 检测到播放器内系列多季组件，测试切季交互');
      // 精确在 PlayerScreen 内部寻找可切换的季按钮（排除已被盖在底部的 DetailScreen）
      Finder targetSeasonFinder = find.descendant(
        of: find.byType(PlayerScreen),
        matching: find.text('第 2 季'),
      );
      if (targetSeasonFinder.evaluate().isEmpty) {
        targetSeasonFinder = find.descendant(
          of: find.byType(PlayerScreen),
          matching: find.textContaining('2 季'),
        );
      }
      if (targetSeasonFinder.evaluate().isEmpty) {
        targetSeasonFinder = find.descendant(
          of: find.byType(PlayerScreen),
          matching: find.byWidgetPredicate((w) =>
              w is InkWell &&
              w.onTap != null &&
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('player-season-')),
        );
      }

      if (targetSeasonFinder.evaluate().isNotEmpty) {
        print('>>> 点击切换至目标季');
        await tester.tap(targetSeasonFinder.first);

        // 探测底部的“正在切换至...”提示浮层即时出现
        final noticeFinder = find.textContaining('正在切换至');
        var noticeShown = false;
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (noticeFinder.evaluate().isNotEmpty) {
            noticeShown = true;
            break;
          }
        }
        expect(noticeShown, isTrue, reason: '切季应即时展示切换提示浮层');
        print('>>> 底部提示浮层已成功出现');

        // 验证 1.8 秒后浮层已自动退场消失（不积压、快速消失）
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.textContaining('正在切换至'), findsNothing, reason: '提示浮层应在短时间内自动退场消失');
        print('>>> 提示浮层已快速干净退场，无残留积压');

        // 等待新季载入与起播（用循环 pump 代替 pumpAndSettle 避免视频帧挂起）
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(find.textContaining('无法从数据源'), findsNothing);
        print('>>> 切换后的新季已成功起播');
      } else {
        print('>>> 提示：未找到可切换的季按钮');
      }
    } else {
      print('>>> 提示：当前短剧未展示系列多季条目');
    }

    print('>>> 🎉 iOS 模拟器 UI 自动化测试全部圆满通过！');
  });
}
