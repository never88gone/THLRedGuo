import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/core/account/hongguo_account_session.dart';
import 'package:THLRedLook/core/account/hongguo_verification.dart';
import 'package:THLRedLook/core/account/hongguo_verification_sdk.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in ['server-fp', 'stored-fp', 'new-fp']) {
    testWidgets('官方SDK与THL合成验证回调使用相同指纹：$scenario', (tester) async {
      PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
      final completion = Completer<bool>();
      final aligned = Completer<bool>();
      var readyCount = 0;
      final pageID = HongguoVerificationChallenge.newPageID();
      const storedFP = 'verify_synthetic_stored_1234567890';
      const serverFP = 'verify_synthetic_server_1234567890';
      final expected = scenario == 'server-fp'
          ? serverFP
          : scenario == 'stored-fp'
          ? storedFP
          : null;
      final cookies = HongguoAccountCookies()
        ..merge(
          Uri.parse(HongguoVerificationChallenge.origin),
          scenario == 'new-fp' ? [] : ['s_v_web_id=$storedFP; Path=/; Secure'],
        );
      final challenge = HongguoVerificationChallenge.fromResult({
        'rejected': true,
        'errorCode': 1105,
        'verification': {
          'kind': 'captcha',
          'script': HongguoVerificationChallenge.script,
          'aid': '513755',
          'repoId': 579047,
          'origin': HongguoVerificationChallenge.origin,
          'userAgent': 'synthetic-agent',
          'data': jsonEncode({
            'code': 10000,
            'detail': 'synthetic',
            if (scenario == 'server-fp') 'fp': serverFP,
          }),
        },
      }, cookies);
      final sdk = (await tester.runAsync(HongguoVerificationSdk.load))!;
      final instrument =
          '''
const realRender=window.verifySDK.autoRender;
window.verifySDK.autoRender=function(options){
 const result=realRender(options);
 Promise.resolve().then(async()=>{
  try{
   const frame=document.querySelector('iframe');
   const rendered=frame?new URL(frame.src).searchParams.get('fp'):null;
   const current=await window.verifySDK.getCaptchaWebId();
   options.captchaOptions.onResize({w:0,h:0});
   await window.flutter_inappwebview.callHandler('alignment',!!rendered&&rendered===current&&(${jsonEncode(expected)}===null||rendered===${jsonEncode(expected)}));
   options.captchaOptions.onResize({w:320,h:360});
   options.captchaOptions.successCb({code:200,headers:{}},{replay_data:null});
  }catch(_){window.flutter_inappwebview.callHandler('alignment',false);}
 });
 return result;
};''';
      final html = challenge
          .html(pageID, sdk + instrument)
          .replaceFirst(
            RegExp(
              r'<meta http-equiv="Content-Security-Policy" content="[^"]*">',
            ),
            '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'; img-src \'none\'; frame-src \'none\'; connect-src \'none\'">',
          );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppWebView(
              initialSettings: InAppWebViewSettings(
                incognito: true,
                cacheEnabled: false,
                javaScriptEnabled: true,
                isInspectable: false,
              ),
              initialData: InAppWebViewInitialData(
                data: html,
                baseUrl: WebUri(HongguoVerificationChallenge.origin),
              ),
              onConsoleMessage: (_, _) {},
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'alignment',
                  callback: (args) {
                    if (!aligned.isCompleted) {
                      aligned.complete(
                        args.singleOrNull == true && readyCount == 0,
                      );
                    }
                  },
                );
                controller.addJavaScriptHandler(
                  handlerName: 'THLVerify',
                  callback: (args) {
                    if (completion.isCompleted || args.singleOrNull is! Map) {
                      return;
                    }
                    final event = args.single as Map;
                    if (event['id'] != pageID) return;
                    if (event['event'] == 'ready') {
                      readyCount++;
                      return;
                    }
                    final fp = event['fp'];
                    completion.complete(
                      event['event'] == 'success' &&
                          fp is String &&
                          HongguoVerificationChallenge.validFingerprint(fp) &&
                          (expected == null || fp == expected),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
      final end = DateTime.now().add(const Duration(seconds: 30));
      while ((!completion.isCompleted || !aligned.isCompleted) &&
          DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      expect(aligned.isCompleted, true);
      expect(completion.isCompleted, true);
      expect(await aligned.future, true);
      expect(await completion.future, true);
      expect(readyCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  binding.reportData = {
    'syntheticVerificationOnly': true,
    'realSmsSent': false,
    'captchaNetworkBlocked': true,
  };
}
