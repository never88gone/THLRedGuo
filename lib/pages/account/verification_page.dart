import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/account/hongguo_verification.dart';
import '../../core/account/hongguo_verification_sdk.dart';

class HongguoVerificationScreen extends StatefulWidget {
  const HongguoVerificationScreen({super.key, required this.challenge});
  final HongguoVerificationChallenge challenge;
  @override
  State<HongguoVerificationScreen> createState() =>
      _HongguoVerificationScreenState();
}

class _HongguoVerificationScreenState extends State<HongguoVerificationScreen> {
  final pageID = HongguoVerificationChallenge.newPageID();
  bool loading = true, finished = false;
  String? error;
  Timer? expiry;
  late final Future<String> sdk;
  @override
  void initState() {
    super.initState();
    sdk = _loadSdk();
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    expiry = Timer(const Duration(minutes: 2), () {
      if (mounted && !finished) {
        setState(() {
          error = '安全验证等待超时，请返回后重新发起';
          loading = false;
        });
      }
      finished = true;
    });
  }

  Future<String> _loadSdk() async {
    try {
      return await HongguoVerificationSdk.load();
    } catch (_) {
      if (mounted) setState(() => loading = false);
      rethrow;
    }
  }

  @override
  void dispose() {
    finished = true;
    expiry?.cancel();
    super.dispose();
  }

  void receive(List<dynamic> args) {
    if (!mounted || finished || args.length != 1 || args.single is! Map) return;
    final event = args.single as Map;
    if (event['id'] != pageID ||
        event.keys.any((k) => !{'id', 'event', 'fp'}.contains(k))) {
      return;
    }
    switch (event['event']) {
      case 'ready':
        setState(() => loading = false);
      case 'success':
        final fp = event['fp'];
        if (fp is! String ||
            !HongguoVerificationChallenge.validFingerprint(fp)) {
          return;
        }
        finished = true;
        expiry?.cancel();
        Navigator.pop(context, fp);
      case 'cancel':
        finished = true;
        Navigator.pop(context);
      case 'error':
        setState(() {
          loading = false;
          error = '红果安全验证加载失败，请检查网络或改用扫码登录';
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('红果安全验证')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('请手动完成红果官方图形验证，完成后继续本次登录操作。'),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Expanded(
            child: FutureBuilder<String>(
              future: sdk,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      '官方验证组件加载失败，请返回重试或使用扫码登录。\n诊断码：VERIFICATION_SDK_UNAVAILABLE',
                    ),
                  );
                }
                if (!snapshot.hasData) return const SizedBox.shrink();
                return InAppWebView(
                  initialSettings: InAppWebViewSettings(
                    incognito: true,
                    cacheEnabled: false,
                    javaScriptEnabled: true,
                    userAgent: widget.challenge.userAgent,
                    useShouldOverrideUrlLoading: true,
                    javaScriptCanOpenWindowsAutomatically: false,
                    supportMultipleWindows: false,
                    geolocationEnabled: false,
                    mediaPlaybackRequiresUserGesture: true,
                    isInspectable: false,
                    disableContextMenu: true,
                  ),
                  initialData: InAppWebViewInitialData(
                    data: widget.challenge.html(pageID, snapshot.data!),
                    baseUrl: WebUri(HongguoVerificationChallenge.origin),
                  ),
                  onWebViewCreated: (controller) {
                    controller.addJavaScriptHandler(
                      handlerName: 'THLVerify',
                      callback: receive,
                    );
                  },
                  onConsoleMessage: (_, _) {},
                  shouldOverrideUrlLoading: (_, action) async {
                    final url = action.request.url;
                    final host = url?.host;
                    final allowed =
                        url?.toString() == 'about:blank' ||
                        url?.scheme == 'https' &&
                            (host == 'hongguoduanju.com' ||
                                action.isForMainFrame == false &&
                                    {
                                      'rmc.bytedance.com',
                                      'vcs.zijieapi.com',
                                      'verify.zijieapi.com',
                                      'verify.snssdk.com',
                                    }.contains(host));
                    return allowed
                        ? NavigationActionPolicy.ALLOW
                        : NavigationActionPolicy.CANCEL;
                  },
                  onPermissionRequest: (_, request) async => PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.DENY,
                  ),
                );
              },
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消验证'),
          ),
        ],
      ),
    ),
  );
}
