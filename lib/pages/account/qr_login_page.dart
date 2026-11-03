import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:gal/gal.dart';
import '../../core/account/hongguo_account_session.dart';
import '../../core/account/hongguo_account_service.dart';

class HongguoQrLoginScreen extends StatefulWidget {
  const HongguoQrLoginScreen({super.key});
  @override
  State<HongguoQrLoginScreen> createState() => _HongguoQrLoginScreenState();
}

class _HongguoQrLoginScreenState extends State<HongguoQrLoginScreen>
    with WidgetsBindingObserver {
  final service = HongguoAccountService();
  HongguoQrLogin? login;
  Timer? timer;
  String? error;
  bool loading = false;
  bool foreground = true;
  int generation = 0;
  int remaining = 0;
  int failures = 0;
  bool polling = false;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_begin());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    if (login != null) login!.cancelled = true;
    service.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) unawaited(_tick());
  }

  Future<void> _begin() async {
    final current = ++generation;
    timer?.cancel();
    if (login != null) login!.cancelled = true;
    setState(() {
      login = null;
      loading = true;
      error = null;
      failures = 0;
    });
    try {
      final next = await service.begin();
      if (!mounted || current != generation) {
        next.cancelled = true;
        return;
      }
      setState(() {
        login = next;
        remaining = next.expiresAt.difference(DateTime.now()).inSeconds;
      });
      timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (_) {
      if (mounted && current == generation) {
        setState(() => error = '二维码申请失败，请稍后重试');
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> _tick() async {
    final current = login;
    if (!mounted || current == null || current.cancelled) return;
    final seconds = current.expiresAt.difference(DateTime.now()).inSeconds;
    setState(() => remaining = seconds < 0 ? 0 : seconds);
    if (!foreground || polling || failures >= 3) return;
    if (remaining > 0 && remaining % 2 != 0) return;
    polling = true;
    try {
      final complete = await service.poll(current, finalCheck: remaining <= 0);
      if (!mounted || current != login) return;
      if (complete) {
        timer?.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      if (remaining <= 0 && !current.confirmed) {
        timer?.cancel();
        current.cancelled = true;
        setState(() => error = '二维码已过期，请刷新');
        return;
      }
      if (error != null) setState(() => error = null);
      failures = 0;
    } on HongguoAccountFailure catch (failure) {
      if (!mounted || current != login) return;
      failures++;
      if (failure.code == 'QR_EXPIRED' ||
          failure.code == 'CANCELLED' ||
          failures >= 3) {
        timer?.cancel();
        current.cancelled = true;
      }
      setState(
        () => error = failures >= 3 ? '登录查询多次失败，请刷新二维码重试' : failure.message,
      );
    } catch (_) {
      if (mounted) {
        failures++;
        setState(() => error = '网络暂不可用，正在等待重试');
      }
    } finally {
      polling = false;
    }
  }

  Future<void> _saveQr() async {
    final current = login;
    if (saving ||
        current == null ||
        current.cancelled ||
        !current.expiresAt.isAfter(DateTime.now())) {
      return;
    }
    setState(() => saving = true);
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw StateError('album');
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1024, 1024),
        Paint()..color = Colors.white,
      );
      canvas.save();
      canvas.translate(160, 160);
      final painter = QrPainter(
        data: current.url,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      );
      painter.paint(canvas, const Size(704, 704));
      canvas.restore();
      final picture = recorder.endRecording();
      final image = await picture.toImage(1024, 1024);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (!mounted ||
          current != login ||
          current.cancelled ||
          !current.expiresAt.isAfter(DateTime.now()) ||
          bytes == null) {
        throw StateError('expired');
      }
      await Gal.putImageBytes(
        bytes.buffer.asUint8List(),
        name: 'THL-Hongguo-login-${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) {
        final expired =
            current.cancelled ||
            current != login ||
            !current.expiresAt.isAfter(DateTime.now());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              expired
                  ? '二维码已保存，但已过期，请刷新后重新保存'
                  : '已保存，请立即打开红果 App → 扫一扫 → 相册，确认后回到糖葫芦 Haw',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = '二维码保存失败，请检查相册权限及二维码有效期后重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('红果 App 扫码登录')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                const Text(
                  '打开手机红果 App，使用“扫一扫”后确认登录',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (loading)
                  const SizedBox(
                    height: 280,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (login?.confirmed == true && !login!.cancelled)
                  const SizedBox(
                    height: 280,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (login != null && !login!.cancelled)
                  Semantics(
                    label: '红果登录二维码',
                    child: QrImageView(
                      key: ValueKey('hongguo-qr-$generation'),
                      data: login!.url,
                      size: 280,
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.white,
                      semanticsLabel: '红果登录二维码',
                    ),
                  )
                else
                  const SizedBox(
                    height: 220,
                    child: Icon(Icons.timer_off_outlined, size: 80),
                  ),
                const SizedBox(height: 16),
                if (login?.confirmed == true && !login!.cancelled)
                  const Text('手机已确认，正在校验红果账号')
                else if (login != null && !login!.cancelled)
                  Text('等待手机确认，剩余 $remaining 秒'),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!, textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 24),
                if (Platform.isIOS || Platform.isAndroid)
                  OutlinedButton.icon(
                    key: const Key('hongguo-qr-save'),
                    onPressed:
                        saving || remaining <= 0 || login?.cancelled != false
                        ? null
                        : _saveQr,
                    icon: const Icon(Icons.save_alt),
                    label: Text(saving ? '正在保存' : '保存二维码到相册'),
                  ),
                if (Platform.isIOS || Platform.isAndroid)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '保存后到红果 App 的“扫一扫”中选择相册图片并确认，随后返回此页面。二维码过期后需要重新保存。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                FilledButton(
                  onPressed: loading ? null : _begin,
                  child: const Text('刷新二维码'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
