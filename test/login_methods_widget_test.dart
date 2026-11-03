import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/pages/account/login_page.dart';
import 'package:THLRedLook/pages/account/phone_login_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final account = HongguoAccountSession.shared;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await account.bindProfile('synthetic-login-navigation');
    final cookies = HongguoAccountCookies()
      ..merge(Uri.parse('https://hongguoduanju.com/'), [
        'sessionid=synthetic-navigation; Path=/; Secure',
      ]);
    await account.accept(cookies, {
      'id': '123',
    }, expectedRevision: account.revision);
  });
  tearDown(account.logout);
  testWidgets('已有账号取消手机号登录仅返回方式选择，不误退首页或弹出根路由', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('合成首页')),
      ),
    );
    unawaited(
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const HongguoLoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hongguo-login-password')), findsNothing);
    await tester.tap(find.byKey(const Key('hongguo-login-sms')));
    await tester.pumpAndSettle();
    expect(find.byType(HongguoPhoneLoginScreen), findsOneWidget);
    expect(find.text('密码'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HongguoLoginScreen), findsOneWidget);
    expect(find.byKey(const Key('hongguo-login-qr')), findsOneWidget);
    expect(account.id, '123');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('合成首页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
