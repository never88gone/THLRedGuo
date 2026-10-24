import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';

const _mockDrama = Drama(
  id: 'hongguo:7697912764613807166',
  source: 'hongguo',
  title: '都市超级战神',
  episodes: 80,
  category: '都市',
  tags: ['都市逆袭', '战神归来', '爽文', '豪门'],
  cover: 'https://example.com/cover.jpg',
  description: '一代战神退役归来，发现家中变故...',
);

class _MockDetailRepository extends AppRepository {
  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';

  @override
  Future<DramaDetail> detail(Drama drama) async {
    return DramaDetail(
      drama,
      [
        for (var i = 1; i <= 80; i++)
          Episode({'id': 'ep_$i', 'title': '第 $i 集', 'currentEpisode': i}, i),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('剧集详情页：标签与追剧控件移入海报右侧，追剧弹窗支持现代多状态切换与移除', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final repository = _MockDetailRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          drama: _mockDrama,
          repository: repository,
          store: store,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. 验证标签出现在海报图片右侧
    expect(find.text('都市逆袭'), findsOneWidget);
    expect(find.text('战神归来'), findsOneWidget);
    expect(find.text('爽文'), findsOneWidget);

    // 2. 验证初始状态下追剧按钮显示“追剧”
    final followBtn = find.byKey(const ValueKey('follow-status'));
    expect(followBtn, findsOneWidget);
    expect(find.text('追剧'), findsOneWidget);

    // 3. 点击追剧按钮，弹出现代化弹窗
    await tester.tap(followBtn);
    await tester.pumpAndSettle();

    // 验证弹窗内容
    expect(find.text('追剧与观看状态'), findsOneWidget);
    expect(find.text('想看'), findsOneWidget);
    expect(find.text('在看'), findsOneWidget);
    expect(find.text('已看'), findsOneWidget);
    expect(find.text('正在追更中，首页常驻快速观看'), findsOneWidget);

    // 此时未追剧，不应显示“从追剧清单中移出”
    expect(find.text('从追剧清单中移出'), findsNothing);

    // 4. 选择“在看”状态
    await tester.tap(find.text('在看'));
    await tester.pumpAndSettle();

    // 验证弹窗已关闭，追剧按钮变为“在看”
    expect(find.text('追剧与观看状态'), findsNothing);
    expect(find.text('在看'), findsOneWidget);

    // 5. 再次点击追剧按钮打开弹窗
    await tester.tap(find.byKey(const ValueKey('follow-status')));
    await tester.pumpAndSettle();

    // 验证弹窗中出现“从追剧清单中移出”
    expect(find.text('从追剧清单中移出'), findsOneWidget);

    // 6. 点击“从追剧清单中移出”
    await tester.tap(find.text('从追剧清单中移出'));
    await tester.pumpAndSettle();

    // 验证弹窗关闭，状态恢复为“追剧”
    expect(find.text('追剧与观看状态'), findsNothing);
    expect(find.text('追剧'), findsOneWidget);
  });

  testWidgets('剧集详情页：海报卡片升级为大图，支持点击全屏大图预览，且简介与播放信息具备高对比衬底', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final repository = _MockDetailRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          drama: _mockDrama,
          repository: repository,
          store: store,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 1. 验证海报封面升级为 126x189 大图尺寸
    final coverHero = find.byKey(const ValueKey('drama-cover-preview'));
    expect(coverHero, findsOneWidget);

    // 2. 验证简介与提示文字正常渲染
    expect(find.text('一代战神退役归来，发现家中变故...'), findsOneWidget);

    // 3. 点击海报封面，打开大图预览弹窗
    await tester.tap(coverHero);
    await tester.pumpAndSettle();

    // 验证全屏大图预览弹窗呈现，带有关闭按钮
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // 点击关闭按钮关闭弹窗
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
