import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:THLRedLook/core/account/hongguo_verification.dart';
import 'package:THLRedLook/core/account/hongguo_verification_sdk.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iOS临时WebView基础HTML与原生桥接，不加载任何远程资源', (tester) async {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    final ready = Completer<void>();
    final phases = <String>[];
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
              baseUrl: WebUri(HongguoVerificationChallenge.origin),
              data:
                  """<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'"><body>WebKit ready<script>function ready(){window.flutter_inappwebview.callHandler('ready');}if(window.flutter_inappwebview&&window.flutter_inappwebview.callHandler)ready();else window.addEventListener('flutterInAppWebViewPlatformReady',ready,{once:true});</script></body>""",
            ),
            onWebViewCreated: (controller) {
              phases.add('created');
              controller.addJavaScriptHandler(
                handlerName: 'ready',
                callback: (_) {
                  if (!ready.isCompleted) {
                    ready.complete();
                  }
                },
              );
            },
            onLoadStart: (_, _) {
              phases.add('start');
            },
            onLoadStop: (_, _) {
              phases.add('loaded');
            },
            onConsoleMessage: (_, _) {},
          ),
        ),
      ),
    );
    final end = DateTime.now().add(const Duration(seconds: 25));
    while (!ready.isCompleted && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    expect(ready.isCompleted, true, reason: phases.join(','));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('iOS临时WebView加载官方验证SDK和匿名指纹，不发送短信或渲染验证图片', (tester) async {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    final result = Completer<bool>();
    final phases = <String>[];
    InAppWebViewController? web;
    bool inspected = false;
    final pageID = HongguoVerificationChallenge.newPageID();
    final sdkSource = (await tester.runAsync(HongguoVerificationSdk.load))!;
    final encodedSource = jsonEncode(sdkSource).replaceAll('<', r'\u003c');
    final html =
        """<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://lf-rc1.yhgfb-cn-static.com; connect-src 'none'; img-src 'none'; frame-src 'none'; style-src 'unsafe-inline'"><script>
function load(){const s=document.createElement('script');s.onload=async()=>{try{const sdk=window.verifySDK;sdk.initVerifyOptions({commonOptions:{aid:513755,iid:'0',did:'0',repoId:579047},captchaOptions:{logConfig:{sample_rate:0}}});const fp=await sdk.getCaptchaWebId();document.cookie='thl_smoke=$pageID; Path=/; Secure';const ok=typeof fp==='string'&&fp.startsWith('verify_')&&fp.length>16&&document.cookie.includes('thl_smoke=$pageID');window.flutter_inappwebview.callHandler('smoke',ok);}catch(_){window.flutter_inappwebview.callHandler('smoke',false);}};s.textContent=$encodedSource;document.head.appendChild(s);s.onload();}if(window.flutter_inappwebview&&window.flutter_inappwebview.callHandler)load();else window.addEventListener('flutterInAppWebViewPlatformReady',load,{once:true});</script>""";
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
            onConsoleMessage: (_, message) {
              if (message.message.contains('Content Security Policy')) {
                phases.add('CSP');
              }
            },
            onReceivedError: (_, _, error) {
              phases.add('network-error');
            },
            onLoadStart: (_, _) {
              phases.add('start');
            },
            onLoadStop: (controller, _) async {
              final state = await controller.evaluateJavascript(
                source:
                    "JSON.stringify({bridge:!!window.flutter_inappwebview,sdk:!!window.verifySDK,secure:window.isSecureContext})",
              );
              phases.add('load:$state');
            },
            onWebViewCreated: (controller) {
              phases.add('created');
              web = controller;
              controller.addJavaScriptHandler(
                handlerName: 'smoke',
                callback: (args) {
                  if (!result.isCompleted) {
                    result.complete(args.singleOrNull == true);
                  }
                },
              );
            },
          ),
        ),
      ),
    );
    final end = DateTime.now().add(const Duration(seconds: 45));
    while (!result.isCompleted && DateTime.now().isBefore(end)) {
      if (!inspected &&
          web != null &&
          end.difference(DateTime.now()).inSeconds < 35) {
        inspected = true;
        await tester.runAsync(() async {
          try {
            final state = await web!
                .evaluateJavascript(
                  source:
                      "JSON.stringify({state:document.readyState,bridge:!!window.flutter_inappwebview,sdk:!!window.verifySDK,scripts:document.scripts.length})",
                )
                .timeout(const Duration(seconds: 5));
            phases.add('probe:$state');
          } catch (_) {
            phases.add('probe-timeout');
          }
        });
      }
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    expect(result.isCompleted, true, reason: phases.join(','));
    expect(await result.future, true);
    binding.reportData = {
      'officialSdkInitialization': true,
      'ephemeralWebView': true,
      'smsRequests': 0,
      'captchaImagesRequested': 0,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
