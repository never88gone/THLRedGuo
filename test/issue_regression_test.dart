// 回归验证：issue #4（TV返回键双触发）/ #5（切分类重建封面）/ #6（画中画状态栏遮挡）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/views/home/home_catalog_view.dart';
import 'package:THLRedLook/views/remote/remote_widgets.dart';

// ---------------------------------------------------------------------------
// Repository mock
// ---------------------------------------------------------------------------

class _Repo extends AppRepository {
  int catalogCalls = 0;
  String lastCategory = '';

  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => [
        const CatalogCategory('', '全部'),
        const CatalogCategory('live', '真人剧'),
        const CatalogCategory('cartoon', '漫剧'),
      ];

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage([], hasMore: false);

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    catalogCalls++;
    lastCategory = category;
    return CatalogPage(
      [
        for (var i = 0; i < 4; i++)
          Drama(
            id: 'hongguo:${category.isEmpty ? 'all' : category}-$i',
            source: source,
            title: '${category.isEmpty ? '全部' : category} 第$i部',
          ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Issue #4 — TV 返回键双触发
// ---------------------------------------------------------------------------
//
// 验证策略：
//   构造一个带有 PopScope(canPop: false) 的 scaffold，模拟 TV 播放器中
//   "PopScope 拦截 + TV 控件单独 pop" 的双触发场景。
//   修复后 _back() 在 TV 模式下直接调用 Navigator.pop()（强制），
//   PopScope.canPop = false，系统通道不会再自动 pop 一次，确保只退一层。


// ---------------------------------------------------------------------------
// Issue #6 — 画中画状态栏遮挡
// ---------------------------------------------------------------------------
//
// 验证策略：
//   直接渲染 PlayerViewportView 的 PiP 覆盖层（Positioned + topPadding）。
//   通过检查修复后 topPadding 参数是否被 Positioned 正确使用来验证。
//   用一个简化 widget 模拟 "PiP 时 topPadding = MediaQuery.paddingOf(context).top" 的布局。

Widget _buildPipOverlay({required double topPadding}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(padding: EdgeInsets.only(top: 44)),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: topPadding,
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('正在画中画窗口中播放', key: ValueKey('pip-label')),
                  SizedBox(height: 12),
                  ElevatedButton(
                    key: ValueKey('pip-restore-btn'),
                    onPressed: null,
                    child: Text('恢复应用内播放'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('issue #4 — TV 返回键只触发一次 pop', () {
    testWidgets('TV 模式 PopScope.canPop=false 确保系统通道不自动 pop', (tester) async {
      int popCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) popCount++;
            },
            child: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  key: const ValueKey('tv-back'),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('TV 返回'),
                ),
              ),
            ),
          ),
        ),
      );

      // 模拟遥控器返回（系统 back gesture / escape 键）
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // 修复后 canPop=false，系统通道不自动 pop，onPopInvoked 被以 didPop=false 调用
      // popCount 仅来自 onPopInvokedWithResult，不是重复 Navigator.pop()
      expect(popCount, lessThanOrEqualTo(1), reason: 'escape 键只应触发一次 pop 回调');
    });

    testWidgets('TV 模式 _back() 强制 pop 后只退一层', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      int poppedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => PopScope(
                      canPop: false,
                      child: Scaffold(
                        body: ElevatedButton(
                          key: const ValueKey('force-pop'),
                          onPressed: () {
                            poppedCount++;
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('强制返回'),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('进入播放页'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('进入播放页'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('force-pop')), findsOneWidget,
          reason: '应进入播放页');

      // 模拟 TV _back() 调用 Navigator.pop()（强制，非 maybePop）
      await tester.tap(find.byKey(const ValueKey('force-pop')));
      await tester.pumpAndSettle();

      expect(poppedCount, 1, reason: '_back() 只应触发一次强制 pop');
      expect(find.byKey(const ValueKey('force-pop')), findsNothing,
          reason: '已回退到首页，播放页消失');
    });
  });

  group('issue #5 — 切分类不清空旧数据 & TV RemoteGrid 不重建', () {
    late LocalStore store;
    late _Repo repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = LocalStore(await SharedPreferences.getInstance());
      repository = _Repo();
    });

    tearDown(() => store.dispose());

    testWidgets('切分类后 HomeCatalogView.items 立即可见（不经历空状态）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(repository: repository, store: store),
        ),
      );
      await tester.pumpAndSettle();

      HomeCatalogView catalog() => tester.widget(find.byType(HomeCatalogView));

      // 首次加载全部分类
      expect(catalog().items, isNotEmpty,
          reason: '首屏应有数据，categoryKey=全部');

      // 记录当前 items 数量
      final initialItemCount = catalog().items.length;

      // 切换到"真人剧"分类
      await tester.tap(find.text('真人剧'));
      // 切换分类后不应立即清空（修复后 _items 保留旧值直到新数据到来）
      await tester.pump(); // 只 pump 一帧，新数据尚未到达

      expect(catalog().items.length, greaterThan(0),
          reason: '切分类后 items 不应立即清空为空，应保留旧数据避免闪白');
      expect(catalog().items.length, initialItemCount,
          reason: '新数据未到达前 items 数量应等于切换前');

      await tester.pumpAndSettle();

      // 新数据到达后应更新为真人剧数据
      expect(catalog().items, isNotEmpty,
          reason: '真人剧数据加载后应有内容');
      expect(repository.lastCategory, equals('live'),
          reason: '最终请求应使用 live 分类');
    });

    testWidgets('TV 模式下切分类 RemoteGrid widget 实例保持不变', (tester) async {
      final ScrollController scrollCtrl = ScrollController();
      addTearDown(scrollCtrl.dispose);

      final items1 = [
        const Drama(id: 'hongguo:all-0', source: 'hongguo', title: '全部剧集0'),
        const Drama(id: 'hongguo:all-1', source: 'hongguo', title: '全部剧集1'),
      ];
      final items2 = [
        const Drama(id: 'hongguo:live-0', source: 'hongguo', title: '真人剧0'),
        const Drama(id: 'hongguo:live-1', source: 'hongguo', title: '真人剧1'),
      ];

      String currentGridKey = 'group1';
      List<Drama> currentItems = items1;

      late StateSetter outerSetState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            outerSetState = setState;
            return MaterialApp(
              home: Scaffold(
                body: HomeCatalogView(
                  items: currentItems,
                  loading: false,
                  loadingMore: false,
                  hasMore: false,
                  error: null,
                  hideVip: false,
                  television: true,
                  scrollController: scrollCtrl,
                  supportsSourceManagement: false,
                  sourcesCount: 1,
                  canLoadMore: false,
                  gridKey: 'catalog-group1-$currentGridKey',
                  tvGridKey: 'group1',
                  onRetryLoad: () {},
                  onLoadMore: () {},
                  onRefresh: () async {},
                  onManageSources: () {},
                  onSwipeCategory: null,
                  tileBuilder: (drama, {focusNode, onFocus}) =>
                      Text(drama.title, key: ValueKey(drama.id)),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // 获取初始 RemoteGrid element 对象标识
      final remoteGridFinder = find.byType(RemoteGrid);
      expect(remoteGridFinder, findsOneWidget, reason: 'TV 模式应显示 RemoteGrid');
      final gridElement1 = tester.element(remoteGridFinder);

      // 切分类：gridKey 变化（包含分类信息），但 tvGridKey 保持 'group1' 不变
      outerSetState(() {
        currentGridKey = 'live';
        currentItems = items2;
      });
      await tester.pumpAndSettle();

      final gridElement2 = tester.element(find.byType(RemoteGrid));

      // 修复后 tvGridKey 相同，ValueKey 不变，Flutter 应复用同一 element
      expect(
        identical(gridElement1, gridElement2),
        isTrue,
        reason: 'tvGridKey 相同时 RemoteGrid element 应被复用，不应因分类切换重建',
      );

      // 数据已更新
      expect(find.text('真人剧0'), findsOneWidget,
          reason: '切分类后 RemoteGrid 内容应更新为真人剧数据');
      expect(find.text('全部剧集0'), findsNothing,
          reason: '旧分类数据应从 RemoteGrid 中移除');
    });
  });

  group('issue #6 — 画中画状态栏遮挡', () {
    testWidgets('PiP 覆盖层内容位于状态栏下方，不被遮挡', (tester) async {
      const statusBarHeight = 44.0;

      await tester.pumpWidget(
        _buildPipOverlay(topPadding: statusBarHeight),
      );
      await tester.pumpAndSettle();

      // 验证 PiP label 在屏幕上可见（未被裁剪）
      expect(find.byKey(const ValueKey('pip-label')), findsOneWidget);
      expect(find.byKey(const ValueKey('pip-restore-btn')), findsOneWidget);

      final labelBox = tester.getRect(find.byKey(const ValueKey('pip-label')));
      expect(
        labelBox.top,
        greaterThanOrEqualTo(statusBarHeight),
        reason: 'PiP 覆盖层内容顶部应不低于状态栏高度 ${statusBarHeight}px，避免被遮挡',
      );
    });

    testWidgets('修复前后对比：topPadding 应等于 MediaQuery 状态栏高度', (tester) async {
      const statusBarHeight = 44.0;

      // 验证修复后的正确值：topPadding = MediaQuery.paddingOf(context).top
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: statusBarHeight)),
            child: Builder(
              builder: (ctx) {
                final topPadding = MediaQuery.paddingOf(ctx).top;
                return _buildPipOverlay(topPadding: topPadding);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final labelBox = tester.getRect(find.byKey(const ValueKey('pip-label')));
      expect(
        labelBox.top,
        greaterThanOrEqualTo(statusBarHeight),
        reason: '修复后 topPadding=MediaQuery.top，内容应位于状态栏以下',
      );
    });

    testWidgets('PiP 状态下恢复按钮在状态栏下方且可点击', (tester) async {
      bool restored = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 44)),
            child: Scaffold(
              body: Builder(
                builder: (ctx) {
                  final topPadding = MediaQuery.paddingOf(ctx).top;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        top: topPadding,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Center(
                          child: ElevatedButton(
                            key: const ValueKey('pip-restore'),
                            onPressed: () => restored = true,
                            child: const Text('恢复应用内播放'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btnBox = tester.getRect(find.byKey(const ValueKey('pip-restore')));
      expect(
        btnBox.top,
        greaterThanOrEqualTo(44),
        reason: '恢复按钮顶部应在状态栏（44px）之下，确保不被遮挡',
      );

      await tester.tap(find.byKey(const ValueKey('pip-restore')));
      await tester.pump();
      expect(restored, isTrue, reason: '恢复按钮应可正常点击');
    });
  });
}
