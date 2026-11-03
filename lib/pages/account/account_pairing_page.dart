import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/account/account_pairing_crypto.dart';
import '../../core/account/account_pairing_service.dart';
import '../../core/account/hongguo_account_session.dart';

class AccountPairingReceiveScreen extends StatefulWidget {
  const AccountPairingReceiveScreen({super.key, required this.deviceName});
  final String deviceName;
  @override
  State<AccountPairingReceiveScreen> createState() =>
      _AccountPairingReceiveScreenState();
}

class _AccountPairingReceiveScreenState
    extends State<AccountPairingReceiveScreen>
    with WidgetsBindingObserver {
  AccountPairingReceiver? receiver;
  String? error;
  bool starting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<bool> _approve(String id) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('切换红果账号？'),
          content: Text(
            '本设备已有红果账号，是否替换为手机授权的账号（尾号 ${id.length > 4 ? id.substring(id.length - 4) : id}）？本地资料会保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('切换账号'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _start() async {
    if (starting) return;
    final old = receiver;
    receiver = null;
    old?.dispose();
    setState(() {
      starting = true;
      error = null;
    });
    final next = AccountPairingReceiver(approveReplacement: _approve);
    receiver = next;
    next.onAccepted = () {
      if (mounted) Navigator.pop(context, true);
    };
    try {
      await next.start(name: widget.deviceName);
    } catch (_) {
      if (mounted) setState(() => error = '无法准备设备配对，请确认两端在同一局域网');
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      receiver?.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    receiver?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('手机糖葫芦 Haw 扫码登录')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AnimatedBuilder(
              animation: receiver ?? const AlwaysStoppedAnimation(0),
              builder: (context, _) => Column(
                children: [
                  const Text(
                    '手机与本设备连接同一局域网，在已登录的糖葫芦 Haw 中选择“扫一扫登录其他设备”，扫码并确认。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (starting)
                    const SizedBox(
                      height: 280,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (receiver?.active == true)
                    QrImageView(
                      key: const Key('haw-account-pair-qr'),
                      data: receiver!.code!.encode(),
                      size: 280,
                      padding: const EdgeInsets.all(20),
                      backgroundColor: Colors.white,
                      semanticsLabel: '糖葫芦 Haw 设备登录配对码',
                    )
                  else
                    const SizedBox(
                      height: 240,
                      child: Icon(Icons.timer_off_outlined, size: 80),
                    ),
                  const SizedBox(height: 16),
                  Text(error ?? receiver?.message ?? '正在准备'),
                  if (receiver?.active == true)
                    Text(
                      '设备：${receiver!.code!.name} · ${receiver!.code!.host}',
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('haw-account-pair-refresh'),
                    onPressed: starting ? null : _start,
                    child: const Text('重新生成配对码'),
                  ),
                  const SizedBox(height: 12),
                  const Text('仅在手机确认后传递当前账号，会话在局域网内加密传输。'),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AccountPairingScanScreen extends StatefulWidget {
  const AccountPairingScanScreen({super.key});
  @override
  State<AccountPairingScanScreen> createState() =>
      _AccountPairingScanScreenState();
}

class _AccountPairingScanScreenState extends State<AccountPairingScanScreen>
    with WidgetsBindingObserver {
  final camera = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  AccountPairingSender? sender;
  String? error;
  bool busy = false, ready = false, disposing = false, cameraStarting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startCamera());
  }

  Future<void> _startCamera() async {
    if (cameraStarting || disposing) return;
    cameraStarting = true;
    try {
      await camera.start();
    } catch (_) {
      if (mounted && !disposing) {
        setState(() => error = '无法使用摄像头，请在系统设置中允许相机权限');
      }
    } finally {
      cameraStarting = false;
    }
  }

  Future<void> _stopCamera() async {
    try {
      await camera.stop();
    } catch (_) {}
  }

  Future<void> _detected(BarcodeCapture capture) async {
    if (busy || ready || disposing) return;
    final raw = capture.barcodes
        .map((v) => v.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final code = AccountPairingCode.parse(raw);
      await camera.stop();
      final next = AccountPairingSender(code);
      sender = next;
      await next.prepare();
      if (mounted && !disposing) setState(() => ready = true);
    } catch (_) {
      sender?.dispose();
      sender = null;
      if (mounted && !disposing) {
        setState(() => error = '配对码无效、已过期或无法连接设备，请确认两端在同一局域网');
      }
    } finally {
      if (mounted && !disposing) setState(() => busy = false);
    }
  }

  Future<void> _send() async {
    if (busy || sender == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await sender!.sendConfirmed();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('接收设备已登录红果账号')));
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '设备未确认登录，请查看接收端结果；原有本地资料会保留。需要重试时请生成新配对码。');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _retry() async {
    sender?.dispose();
    sender = null;
    setState(() {
      ready = false;
      error = null;
    });
    await _startCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!ready && !busy) unawaited(_startCamera());
    } else {
      unawaited(_stopCamera());
    }
  }

  @override
  void dispose() {
    disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    sender?.dispose();
    unawaited(camera.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫一扫登录其他设备')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ready
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.devices, size: 64),
                          const SizedBox(height: 20),
                          Text(
                            '登录到 ${sender!.receiverName}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(sender!.code.host),
                          const SizedBox(height: 20),
                          Text(
                            '将当前红果账号“${HongguoAccountSession.shared.nickname}”的会话发送到此设备。',
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            key: const Key('haw-account-pair-send'),
                            onPressed: busy ? null : _send,
                            child: Text(busy ? '正在验证并登录' : '确认登录到此设备'),
                          ),
                        ],
                      ),
                    ),
                  )
                : MobileScanner(
                    controller: camera,
                    onDetect: (capture) => unawaited(_detected(capture)),
                    errorBuilder: (context, error) =>
                        const Center(child: Text('摄像头不可用，请检查相机权限')),
                  ),
          ),
          if (busy && !ready) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error ?? '只扫描电视或电脑上显示的糖葫芦 Haw 登录配对码。',
              textAlign: TextAlign.center,
            ),
          ),
          if (error != null)
            TextButton(
              onPressed: busy ? null : _retry,
              child: const Text('重新扫码'),
            ),
        ],
      ),
    ),
  );
}
