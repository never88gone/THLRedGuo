import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/account/hongguo_verification.dart';
import '../../core/diagnostics/source_diagnostics.dart';
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
  Timer? expiry, loadProbe;
  InAppWebViewController? verificationWebView;
  late final Future<String> sdk;
  @override
  void initState() {
    super.initState();
    sdk = _loadSdk();
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    expiry = Timer(const Duration(minutes: 2), () {
      if (mounted && !finished) {
        _recordVerificationDiagnostic(
          '安全验证超时',
          code: loading ? 'VERIFICATION_LOAD_TIMEOUT' : 'VERIFICATION_EXPIRED',
        );
        unawaited(_captureVerificationState());
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
    loadProbe?.cancel();
    verificationWebView = null;
    super.dispose();
  }

  void _recordVerificationDiagnostic(
    String stage, {
    Uri? url,
    String code = '',
    String status = '',
    int httpStatus = 0,
  }) {
    if (!mounted) return;
    SourceDiagnostics.shared.add(
      SourceDiagnosticEntry(
        at: DateTime.now(),
        context: '红果登录',
        stage: stage,
        host: url?.host ?? '',
        errorCode: code,
        sessionStatus: status,
        status: httpStatus,
      ),
    );
  }

  Future<void> _captureVerificationState() async {
    final controller = verificationWebView;
    if (controller == null || !mounted) return;
    try {
      final metadata = await controller.evaluateJavascript(
        source: """
(() => {
 const host = value => {try {return new URL(value, location.href).hostname;} catch (_) {return '';}};
 return JSON.stringify({
  state:document.readyState,
  sdk:!!window.verifySDK,
  frames:Array.from(document.querySelectorAll('iframe')).slice(0,8).map(frame => ({
   host:host(frame.src), visible:frame.style.visibility!=='hidden',
   width:frame.clientWidth, height:frame.clientHeight
  })),
  resources:performance.getEntriesByType('resource').filter(entry =>
   ['iframe','script','fetch','xmlhttprequest'].includes(entry.initiatorType)
  ).slice(-8).map(entry => ({host:host(entry.name),type:entry.initiatorType,
   duration:Math.round(entry.duration),status:entry.responseStatus||0}))
 });
})()
""",
      );
      if (mounted && metadata is String && metadata.length <= 4096) {
        _recordVerificationDiagnostic('验证页面加载状态', status: metadata);
      }
    } catch (_) {
      _recordVerificationDiagnostic(
        '验证页面加载状态',
        code: 'VERIFICATION_STATE_UNAVAILABLE',
      );
    }
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
        loadProbe?.cancel();
        setState(() => loading = false);
      case 'success':
        final fp = event['fp'];
        if (fp is! String ||
            !HongguoVerificationChallenge.validFingerprint(fp)) {
          return;
        }
        finished = true;
        expiry?.cancel();
        _recordVerificationDiagnostic('安全验证完成');
        Navigator.pop(context, fp);
      case 'cancel':
        finished = true;
        Navigator.pop(context);
      case 'error':
        finished = true;
        expiry?.cancel();
        _recordVerificationDiagnostic(
          '安全验证渲染',
          code: 'VERIFICATION_RENDER_ERROR',
        );
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
                  key: ValueKey(pageID),
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
                    verificationWebView = controller;
                    loadProbe = Timer(const Duration(seconds: 15), () {
                      if (mounted && loading && !finished) {
                        unawaited(_captureVerificationState());
                      }
                    });
                    controller.addJavaScriptHandler(
                      handlerName: 'THLVerify',
                      callback: receive,
                    );
                  },
                  onConsoleMessage: (_, message) {
                    final text = message.message;
                    if (text.contains('Content Security Policy') ||
                        text.contains('Content Security directive')) {
                      final match = RegExp(
                        r'https://[A-Za-z0-9.-]+',
                      ).firstMatch(text);
                      _recordVerificationDiagnostic(
                        '验证资源策略',
                        url: Uri.tryParse(match?.group(0) ?? ''),
                        code: 'VERIFICATION_CSP',
                      );
                    }
                  },
                  onReceivedError: (_, request, error) =>
                      _recordVerificationDiagnostic(
                        '验证资源连接',
                        url: request.url,
                        code: 'VERIFICATION_RESOURCE_ERROR',
                        status:
                            'mainFrame=${request.isForMainFrame} native=${error.type.toNativeValue()}',
                      ),
                  onReceivedHttpError: (_, request, response) =>
                      _recordVerificationDiagnostic(
                        '验证资源响应',
                        url: request.url,
                        code: 'VERIFICATION_HTTP_ERROR',
                        httpStatus: response.statusCode ?? 0,
                      ),
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
                    _recordVerificationDiagnostic(
                      '验证页面导航',
                      url: url,
                      status:
                          'mainFrame=${action.isForMainFrame} allowed=$allowed',
                    );
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
