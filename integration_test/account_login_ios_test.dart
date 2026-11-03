import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/js/hongguo_guest_session.dart';
import 'package:THLRedLook/pages/account/account_page.dart';
import 'package:THLRedLook/pages/home/home_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('官网扫码申请刷新取消与本地资料保留', (tester) async {
    await app.main([]);
    await _wait(
      tester,
      () => find.byType(HomeScreen).evaluate().isNotEmpty,
      'home bootstrap',
    );
    final root = tester.widget<app.DuanjuApp>(find.byType(app.DuanjuApp));
    final store = root.store!;
    final follows = store.favorites.map((d) => d.id).toSet();
    final beforeRevision = HongguoAccountSession.shared.revision;
    await tester.tap(find.byKey(const ValueKey('bottom-nav-2')));
    await _wait(
      tester,
      () => find.byType(AccountScreen).evaluate().isNotEmpty,
      'personal center',
    );
    expect(find.text('我的'), findsWidgets);
    if (HongguoAccountSession.shared.loggedIn) {
      expect(find.byKey(const Key('hongguo-account-menu')), findsOneWidget);
      return;
    }
    await tester.tap(find.byKey(const Key('hongguo-account-login')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hongguo-login-qr')));
    await _wait(
      tester,
      () => find.byType(QrImageView).evaluate().isNotEmpty,
      'official QR issuance',
      seconds: 50,
    );
    final first =
        (tester.widget<QrImageView>(find.byType(QrImageView)).key!
                as ValueKey<String>)
            .value;
    expect(first, startsWith('hongguo-qr-'));
    final guest = HongguoGuestSession.shared.value;
    await tester.tap(find.text('刷新二维码'));
    await _wait(
      tester,
      () =>
          find.byType(QrImageView).evaluate().isNotEmpty &&
          (tester.widget<QrImageView>(find.byType(QrImageView)).key!
                      as ValueKey<String>)
                  .value !=
              first,
      'fresh login attempt',
      seconds: 40,
    );
    await tester.tap(find.text('取消登录'));
    await _wait(
      tester,
      () => find.byType(HongguoQrLoginScreen).evaluate().isEmpty,
      'cancel returns to account',
    );
    root.navigatorKey!.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(HongguoAccountSession.shared.loggedIn, false);
    expect(HongguoAccountSession.shared.revision, beforeRevision);
    expect(HongguoGuestSession.shared.value, guest);
    expect(store.favorites.map((d) => d.id).toSet(), follows);
    expect(tester.takeException(), isNull);
    binding.reportData = {
      'platform': 'iOS27',
      'qrIssued': true,
      'refreshCreatesNewAttempt': true,
      'cancelReturnsToPersonalCenter': true,
      'guestPreserved': true,
      'favoritesPreserved': true,
      'realAccountAuthorization': false,
      'remoteImagesDisabled': const bool.fromEnvironment(
        'DISABLE_REMOTE_IMAGES',
      ),
    };
  });
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() done,
  String name, {
  int seconds = 90,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  expect(done(), isTrue, reason: name);
}
