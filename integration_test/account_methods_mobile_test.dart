import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:THLRedLook/main.dart' as app;
import 'package:THLRedLook/pages/home/home_page.dart';
import 'package:THLRedLook/pages/account/login_page.dart';
import 'package:THLRedLook/pages/account/phone_login_page.dart';
import 'package:THLRedLook/pages/account/qr_login_page.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/diagnostics/source_diagnostics.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    '手机登录入口、无效手机号阻止发送、二维码PNG保存和原有资料保留',
    (tester) async {
      Future<void> wait(bool Function() ready, {int seconds = 60}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        expect(ready(), true);
      }

      debugPrint('THL_LOGIN_STEP bootstrap');
      await app.main([]);
      debugPrint('THL_LOGIN_STEP app-main-returned');
      await wait(() => find.byType(HomeScreen).evaluate().isNotEmpty);
      debugPrint('THL_LOGIN_STEP home');
      final root = tester.widget<app.DuanjuApp>(find.byType(app.DuanjuApp));
      final store = root.store!;
      expect(store.locked, false);
      final session = HongguoAccountSession.shared,
          originalID = HongguoAccountSession.shared.id;
      String records() => sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'follows': store.favorites.map((v) => v.toJson()).toList(),
                'history': store.history.map((v) => v.toJson()).toList(),
              }),
            ),
          )
          .toString();
      final before = records();
      final navigator = root.navigatorKey!.currentState!;
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const HongguoLoginScreen()),
        ),
      );
      await wait(
        () => find.byKey(const Key('hongguo-login-sms')).evaluate().isNotEmpty,
      );
      debugPrint('THL_LOGIN_STEP chooser');
      expect(find.byKey(const Key('hongguo-login-sms')), findsOneWidget);
      expect(find.byKey(const Key('hongguo-login-password')), findsNothing);
      expect(find.byKey(const Key('hongguo-login-qr')), findsOneWidget);
      await tester.tap(find.byKey(const Key('hongguo-login-sms')));
      await wait(
        () => find.byType(HongguoPhoneLoginScreen).evaluate().isNotEmpty,
      );
      debugPrint('THL_LOGIN_STEP phone');
      expect(find.byType(HongguoPhoneLoginScreen), findsOneWidget);
      await tester.enterText(find.byKey(const Key('login-phone')), '123');
      final sends = SourceDiagnostics.shared.entries
          .where((v) => v.stage == 'phoneCode')
          .length;
      await tester.tap(find.byKey(const Key('phone-send-code')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('手机号格式无效'), findsOneWidget);
      expect(
        SourceDiagnostics.shared.entries
            .where((v) => v.stage == 'phoneCode')
            .length,
        sends,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('login-secret')))
            .keyboardType,
        TextInputType.number,
      );
      await tester.enterText(find.byKey(const Key('login-secret')), '654321');
      await tester.ensureVisible(find.byKey(const Key('phone-login-submit')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const Key('phone-login-submit')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('手机号格式无效'), findsOneWidget);
      navigator.popUntil((route) => route.isFirst);
      await tester.pump(const Duration(milliseconds: 500));
      debugPrint('THL_LOGIN_STEP negative-phone-complete');
      Uint8List? image;
      const channel = MethodChannel('gal');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'hasAccess' || call.method == 'requestAccess') {
              return true;
            }
            if (call.method == 'putImageBytes') {
              image = (call.arguments as Map)['bytes'] as Uint8List;
              return null;
            }
            return null;
          });
      try {
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const HongguoQrLoginScreen(),
            ),
          ),
        );
        await wait(() => find.byType(QrImageView).evaluate().isNotEmpty);
        debugPrint('THL_LOGIN_STEP qr-issued');
        await tester.ensureVisible(find.byKey(const Key('hongguo-qr-save')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byKey(const Key('hongguo-qr-save')));
        await wait(() => image != null, seconds: 30);
        expect(image!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
        final dimensions = ByteData.sublistView(image!);
        expect(dimensions.getUint32(16), 1024);
        expect(dimensions.getUint32(20), 1024);
        navigator.popUntil((route) => route.isFirst);
        await tester.pump(const Duration(milliseconds: 500));
        expect(session.id == originalID, true);
        expect(records() == before, true);
        expect(tester.takeException(), isNull);
        binding.reportData = {
          'loginMethods': true,
          'invalidNumberNoSms': true,
          'passwordEntryAbsent': true,
          'qrSavePng': true,
          'pngSize': 1024,
          'galleryMocked': true,
          'realSmsSent': false,
          'realSessionTransferred': false,
          'localDataPreservedDuringThisRun': true,
          'imagesDisabled': true,
        };
        debugPrint('THL_LOGIN_METHODS ${jsonEncode(binding.reportData)}');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
