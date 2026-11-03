import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/account/hongguo_account_service.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/account/account_page.dart';
import 'package:THLRedLook/views/home/home_app_bar_view.dart';

class _MockRepo extends AppRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockAccountService extends HongguoAccountService {
  @override
  Future<void> verify() async {}

  @override
  Future<List<WatchEntry>> library({required bool history}) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('Tab栏目与账号导航栏改造测试', () {
    testWidgets('HomeAppBarView 去掉所有设置按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: HomeAppBarView(
              selectionMode: false,
              selectedEmpty: true,
              tab: 0,
              sourceGroups: const [],
              group: const SourceGroup('hongguo', '红果短剧', [SourceSite.hongguo]),
              showRecommendations: false,
              searchVisible: false,
              television: false,
              canDownload: true,
              supportsDownloads: true,
              supportsSourceManagement: false,
              sourcesEmpty: false,
              loading: false,
              catalogSortLabel: '默认排序',
              isSortedOrFiltered: false,
              screenWidth: 400,
              onClearSelection: () {},
              onCancelSelection: () {},
              onChangeGroup: (_) {},
              onChooseCatalogView: () {},
              onOpenRankings: () {},
              onStartSelection: () {},
              onToggleSearch: () {},
              onRefreshCatalog: () {},
              onMoreAction: (_) {},
              onOpenSourceSwitcher: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证导航栏不再包含设置按钮
      expect(find.byKey(const ValueKey('home-appbar-settings-button')), findsNothing);
      expect(find.byIcon(Icons.settings_rounded), findsNothing);
    });

    testWidgets('未登录时：我的页面导航栏无设置按钮，登录按钮优化且点击弹出清除提示', (tester) async {
      final session = HongguoAccountSession();
      await session.bindProfile('guest-test-profile');
      final store = LocalStore(await SharedPreferences.getInstance());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountScreen(
              repository: _MockRepo(),
              store: store,
              service: _MockAccountService(),
              session: session,
              localLibraryBuilder: (_) => const SizedBox(),
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 验证标题和登录按钮
      expect(find.text('我的'), findsOneWidget);
      expect(find.byKey(const Key('my-settings')), findsNothing);
      expect(find.byKey(const Key('hongguo-account-login')), findsOneWidget);

      // 2. 点击登录按钮，验证弹出提示弹窗
      await tester.tap(find.byKey(const Key('hongguo-account-login')));
      await tester.pumpAndSettle();

      expect(find.text('账号登录提示'), findsOneWidget);
      expect(
        find.textContaining('登录后将使用短剧平台的接口数据同步追剧与观看记录，原本通过 iCloud 同步的本地记录将被清除'),
        findsOneWidget,
      );
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('确认登录'), findsOneWidget);

      // 点击取消关闭对话框
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('账号登录提示'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('已登录时：左边显示用户头像+名称，右边显示更多按钮（含扫码和退出登录，带图标）', (tester) async {
      final session = HongguoAccountSession();
      await session.bindProfile('logged-in-test-profile');
      await session.accept(
        HongguoAccountCookies([
          {
            'name': 'sessionid',
            'value': 'sess_123',
            'domain': 'hongguoduanju.com',
            'path': '/',
          },
        ]),
        {
          'id': '123456789',
          'nickname': '红果VIP短剧迷',
          'avatar': '',
        },
        expectedRevision: session.revision,
      );
      final store = LocalStore(await SharedPreferences.getInstance());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountScreen(
              repository: _MockRepo(),
              store: store,
              service: _MockAccountService(),
              session: session,
              localLibraryBuilder: (_) => const SizedBox(),
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. 验证左边展示用户名称和头像
      expect(find.text('红果VIP短剧迷'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.byKey(const Key('my-settings')), findsNothing);

      // 2. 验证右边展示更多按钮
      expect(find.byKey(const Key('hongguo-account-more-menu')), findsOneWidget);

      await tester.tap(find.byKey(const Key('hongguo-account-more-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证菜单项及图标示意
      expect(find.text('退出登录'), findsOneWidget);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
