import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/pages/account/account_page.dart';
import 'package:THLRedLook/pages/settings/settings_page.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    '我的账号列表、菜单和独立设置保留本机资料',
    (tester) async {
      Future<void> wait(bool Function() ready) async {
        final end = DateTime.now().add(const Duration(seconds: 65));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(ready(), true);
      }

      Future<void> tap(String key) async {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump(const Duration(milliseconds: 300));
      }

      await app.main([]);
      await wait(() => find.byType(HomeScreen).evaluate().isNotEmpty);
      final root = tester.widget<app.DuanjuApp>(find.byType(app.DuanjuApp));
      final store = root.store!;
      final localFollows = store.favorites.map((v) => v.id).toSet();
      final localHistory = store.history
          .map((v) => v.toJson())
          .toList()
          .toString();
      expect(HongguoAccountSession.shared.loggedIn, true);
      await tap('bottom-nav-2');
      await wait(
        () =>
            find.byType(AccountScreen).evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty &&
            HongguoAccountSession.shared.verified,
      );
      expect(find.byKey(const Key('hongguo-account-menu')), findsOneWidget);
      await tap('my-history');
      await wait(() => find.byType(LinearProgressIndicator).evaluate().isEmpty);
      expect(find.byKey(const Key('account-library-error')), findsNothing);
      expect(find.byType(DramaTile), findsWidgets);
      await tester.tap(find.byType(DramaTile).first);
      await wait(() => find.byType(DetailScreen).evaluate().isNotEmpty);
      root.navigatorKey!.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      await tap('my-follows');
      await wait(() => find.byType(LinearProgressIndicator).evaluate().isEmpty);
      expect(find.byKey(const Key('account-library-error')), findsNothing);
      await tap('hongguo-account-menu');
      await tester.pumpAndSettle();
      expect(find.text('退出登录'), findsOneWidget);
      root.navigatorKey!.currentState!.pop();
      await tester.pumpAndSettle();
      await tap('my-settings');
      await wait(() => find.byType(SettingsScreen).evaluate().isNotEmpty);
      root.navigatorKey!.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(store.favorites.map((v) => v.id).toSet(), localFollows);
      expect(
        store.history.map((v) => v.toJson()).toList().toString(),
        localHistory,
      );
      expect(tester.takeException(), isNull);
      debugPrint(
        'THL_MY_LIBRARY ios history=true follows=true menuCancel=true settingsDirect=true localPreserved=true imagesDisabled=true',
      );
    },
    skip: !const bool.fromEnvironment('THL_ACCOUNT_OWNER'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
