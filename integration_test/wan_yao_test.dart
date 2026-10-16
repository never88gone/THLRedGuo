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

    // 4. 点击立即播放或第1集
    print('>>> [5/6] 点击播放视频');
    final playBtnFinder = find.text('立即播放');
    final ep1Finder = find.text('第 1 集');

    if (playBtnFinder.evaluate().isNotEmpty) {
      await tester.tap(playBtnFinder.first);
    } else if (ep1Finder.evaluate().isNotEmpty) {
      await tester.tap(ep1Finder.first);
    } else {
      fail('未找到播放按钮或第1集按钮');
    }

    await tester.pumpAndSettle(const Duration(seconds: 4));
    expect(find.byType(PlayerScreen), findsOneWidget, reason: '应成功进入 PlayerScreen 播放页');

    // 观察 3 秒起播状态
    print('>>> 播放器已拉起，持续监控视频播放流与渲染...');
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('无法从数据源'), findsNothing);

    // 5. 验证播放器面板中的系列多季切季交互与提示浮层快速消失
    print('>>> [6/6] 验证系列多季切换与底部提示浮层');
    final seriesBarFinder = find.text('系列多季');
    if (seriesBarFinder.evaluate().isNotEmpty) {
      print('>>> 检测到系列多季组件，测试切季交互');
      // 找到第2季的切换按钮
      final season2Finder = find.text('第2季');
      if (season2Finder.evaluate().isNotEmpty) {
        print('>>> 点击切换至“第2季”');
        await tester.tap(season2Finder.first);
        await tester.pump(const Duration(milliseconds: 300));

        // 验证底部的“正在切换至...”提示浮层即时出现
        final noticeFinder = find.textContaining('正在切换至');
        expect(noticeFinder, findsWidgets, reason: '切季应即时展示切换提示浮层');
        print('>>> 底部提示浮层已成功出现');

        // 验证 1.8 秒后浮层已自动退场消失（不积压、快速消失）
        await tester.pump(const Duration(milliseconds: 1800));
        await tester.pump(const Duration(milliseconds: 300));
        expect(noticeFinder, findsNothing, reason: '提示浮层应在短时间内自动退场消失');
        print('>>> 提示浮层已快速干净退场，无残留积压');

        // 等待新季载入与起播
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.textContaining('无法从数据源'), findsNothing);
        print('>>> 切换后的新季已成功起播');
      }
    }

    print('>>> 🎉 iOS 模拟器 UI 自动化测试全部圆满通过！');
  });
}
