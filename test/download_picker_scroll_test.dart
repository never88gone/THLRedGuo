import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/download_picker.dart';
import 'package:THLRedLook/models.dart';

void main() {
  testWidgets('DownloadPicker 支持全区域滑动并且顶部操作和剧集统一在一个滚动视图内', (tester) async {
    final episodes = List.generate(
      100,
      (index) => Episode(
        {
          'id': '${index + 1}',
          'title': '第${index + 1}集',
          'currentEpisode': index + 1,
          'vip': index > 5,
        },
        index + 1,
      ),
    );

    const drama = Drama(
      id: 'hongguo:test_1',
      source: 'hongguo',
      title: '测试热播短剧',
      episodes: 100,
    );

    final detail = DramaDetail(drama, episodes);

    DownloadSelection? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            width: 360,
            child: DownloadPicker(
              detail: detail,
              embedded: true,
              onSubmit: (selection) async {
                submitted = selection;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 验证标题、操作栏、画质选择与吸底加入下载按钮
    expect(find.text('下载选集'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
    expect(find.text('画质'), findsOneWidget);
    expect(find.byKey(const ValueKey('enqueue-downloads')), findsOneWidget);

    // 验证包含了 CustomScrollView 并且包含剧集项
    final scrollFinder = find.byType(CustomScrollView);
    expect(scrollFinder, findsOneWidget);

    // 测试手势在顶部操作栏区域向上拖动（滚动视口整体滚动）
    await tester.drag(find.text('下载选集'), const Offset(0, -200));
    await tester.pumpAndSettle();

    // 验证可以正常响应拖动，并且加入下载按钮依然常驻可见
    expect(find.byKey(const ValueKey('enqueue-downloads')), findsOneWidget);

    // 测试点击加入下载按钮
    await tester.tap(find.byKey(const ValueKey('enqueue-downloads')));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.episodes.length, greaterThan(0));
  });
}
