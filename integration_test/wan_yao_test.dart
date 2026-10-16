import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/widgets.dart';
import 'package:THLRedLook/detail_screen.dart';
import 'package:THLRedLook/player_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS模拟器真机端到端自动化测试：搜索“万妖图录”并播放', (WidgetTester tester) async {
    print('>>> [1/5] 启动 App 并等待首屏渲染');
    await app.main([]);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 1. 点击展开搜索栏
    print('>>> [2/5] 点击搜索图标展开搜索栏');
    final toggleSearchFinder = find.byKey(const ValueKey('toggle-search'));
    if (toggleSearchFinder.evaluate().isNotEmpty) {
      await tester.tap(toggleSearchFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // 2. 输入“万妖图录”进行搜索
    print('>>> [3/5] 输入“万妖图录”并提交搜索');
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
    print('>>> [4/5] 点击进入短剧详情页');
    await tester.tap(dramaTileFinder.first);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byType(DetailScreen), findsOneWidget, reason: '应成功展示短剧详情页');
    print('>>> 详情页加载成功');

    // 4. 点击立即播放或第1集
    print('>>> [5/5] 点击播放视频');
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

    // 观察 5 秒播放状态
    print('>>> 播放器已拉起，持续监控播放状态...');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    // 验证未出现播放失败提示
    expect(find.textContaining('无法从数据源'), findsNothing);
    print('>>> 恭喜！iOS 模拟器端到端自动化测试圆满完成，视频正常起播！');
  });
}
