import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('验证多次触发提示时立即清空队列积压并仅展示最后一次', (WidgetTester tester) async {
    void showNotice(
      BuildContext context,
      String message, {
      Duration duration = const Duration(milliseconds: 1200),
    }) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.clearSnackBars();
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    late BuildContext targetContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              targetContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    // 连续触发 3 次切换提示
    showNotice(targetContext, '正在切换至 第一季...');
    await tester.pump();

    showNotice(targetContext, '正在切换至 第二季...');
    await tester.pump();

    showNotice(targetContext, '正在切换至 第三季...');
    await tester.pump();

    // 此时屏幕上应当只有最后一次的内容“第三季”，前两次已被清除，无队列排队积压
    expect(find.text('正在切换至 第一季...'), findsNothing);
    expect(find.text('正在切换至 第二季...'), findsNothing);
    expect(find.text('正在切换至 第三季...'), findsOneWidget);

    // 1. 进场动画（约 250ms）
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在切换至 第三季...'), findsOneWidget);

    // 2. 持续展示时间（1200ms）后触发退场
    await tester.pump(const Duration(milliseconds: 1300));

    // 3. 退场动画（约 250ms）后完全消失
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('正在切换至 第三季...'), findsNothing);
  });
}
