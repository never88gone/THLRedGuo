import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/models.dart';
import 'package:THLRedLook/views/player/player_quality_sheet_view.dart';
import 'package:THLRedLook/views/player/player_episodes_sheet_view.dart';

void main() {
  group('PlayerQualitySheetView', () {
    testWidgets('渲染画质选项与层级说明并响应点击选择', (tester) async {
      int? selectedQuality;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => PlayerQualitySheetView(
                      qualities: const [1080, 720, 540],
                      selectedQuality: 1080,
                      actualQuality: 1080,
                      isLocal: false,
                      onQualitySelected: (q) {
                        selectedQuality = q;
                      },
                    ),
                  );
                },
                child: const Text('打开画质'),
              ),
            ),
          ),
        ),
      );

      // 打开画质面板
      await tester.tap(find.text('打开画质'));
      await tester.pumpAndSettle();

      expect(find.text('选择播放清晰度'), findsOneWidget);
      expect(find.text('1080P 超清'), findsOneWidget);
      expect(find.text('720P 高清'), findsOneWidget);
      expect(find.text('540P 标清'), findsOneWidget);
      expect(find.text('自动模式'), findsOneWidget);
      expect(find.text('播放中'), findsOneWidget);

      // 点击切换为 720P 高清
      await tester.tap(find.text('720P 高清'));
      await tester.pumpAndSettle();

      // 验证选择回调被触发且抽屉自动关闭
      expect(selectedQuality, 720);
      expect(find.text('选择播放清晰度'), findsNothing);
    });
  });

  group('PlayerEpisodesSheetView', () {
    testWidgets('渲染剧集、支持正序/倒序切换、分组胶囊与切集', (tester) async {
      int? selectedIndex;
      final episodes = List<Episode>.generate(
        70,
        (i) => Episode({'id': 'ep_${i + 1}', 'title': '第 ${i + 1} 集', 'currentEpisode': i + 1}, i + 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (_) => PlayerEpisodesSheetView(
                      episodes: episodes,
                      currentIndex: 5, // 第 6 集
                      onEpisodeSelected: (index) {
                        selectedIndex = index;
                      },
                    ),
                  );
                },
                child: const Text('打开选集'),
              ),
            ),
          ),
        ),
      );

      // 打开选集面板
      await tester.tap(find.text('打开选集'));
      await tester.pumpAndSettle();

      // 验证标题与分组胶囊
      expect(find.text('选集'), findsOneWidget);
      expect(find.text('共 70 集'), findsOneWidget);
      expect(find.text('当前播放：第 6 集'), findsOneWidget);
      expect(find.text('1-30'), findsOneWidget);
      expect(find.text('31-60'), findsOneWidget);
      expect(find.text('61-70'), findsOneWidget);
      expect(find.text('正序'), findsOneWidget);
      expect(find.text('播放中'), findsOneWidget);

      // 点击倒序
      await tester.tap(find.text('正序'));
      await tester.pumpAndSettle();
      expect(find.text('倒序'), findsOneWidget);

      // 切换分组到 31-60
      await tester.tap(find.text('31-60'));
      await tester.pumpAndSettle();

      // 倒序状态下首个即为第 60 集
      expect(find.text('60'), findsOneWidget);
      await tester.tap(find.text('60'));
      await tester.pumpAndSettle();

      // 验证选中的索引是 59（第60集）且抽屉已自动关闭
      expect(selectedIndex, 59);
      expect(find.text('选集'), findsNothing);
    });
  });
}
