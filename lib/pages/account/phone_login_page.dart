import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/account/hongguo_account_service.dart';
import '../../core/account/hongguo_account_session.dart';
import '../../core/account/hongguo_verification.dart';
import 'verification_page.dart';

class HongguoPhoneLoginScreen extends StatefulWidget {
  const HongguoPhoneLoginScreen({super.key});
  @override
  State<HongguoPhoneLoginScreen> createState() =>
      _HongguoPhoneLoginScreenState();
}

class _HongguoPhoneLoginScreenState extends State<HongguoPhoneLoginScreen> {
  final service = HongguoAccountService();
  final country = TextEditingController(text: '86'),
      number = TextEditingController(),
      secret = TextEditingController();
  HongguoPhoneLogin? attempt;
  Timer? timer;
  bool busy = false;
  String? error;
  int remaining = 0;
  DateTime retryAt = DateTime(2000);
  HongguoPhoneLogin _current() {
    if (attempt == null ||
        attempt!.country != country.text ||
        attempt!.number != number.text) {
      if (attempt != null) attempt!.cancelled = true;
      attempt = service.phone(country.text, number.text)..retryAt = retryAt;
    }
    return attempt!;
  }

  Future<void> _perform(Future<void> Function() operation) async {
    if (busy) return;
    final cc = country.text.replaceFirst(RegExp(r'^\+'), '');
    final digits = number.text.replaceAll(RegExp(r'[ ()-]'), '');
    if (!RegExp(r'^[1-9]\d{0,2}$').hasMatch(cc) ||
        !RegExp(cc == '86' ? r'^1\d{10}$' : r'^\d{4,14}$').hasMatch(digits) ||
        cc.length + digits.length > 15) {
      setState(() => error = '手机号格式无效');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } on HongguoAccountFailure catch (e) {
      final code = RegExp(r'^[A-Z][A-Z0-9_-]{0,60}$').hasMatch(e.code)
          ? e.code
          : 'ACCOUNT_FAILED';
      if (mounted) setState(() => error = '${e.message}\n诊断码：$code');
    } catch (_) {
      if (mounted) setState(() => error = '登录请求暂时失败，请稍后再试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _verify(HongguoVerificationChallenge challenge) async {
    if (!mounted) return null;
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => HongguoVerificationScreen(challenge: challenge),
      ),
    );
  }

  Future<void> _send() => _perform(() async {
    final current = _current();
    final seconds = await service.sendPhoneCode(current, verify: _verify);
    retryAt = current.retryAt;
    if (!mounted) return;
    setState(() => remaining = seconds);
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = (retryAt.difference(DateTime.now()).inMilliseconds / 1000)
          .ceil();
      setState(() => remaining = next.clamp(0, 600));
      if (remaining == 0) timer?.cancel();
    });
  });
  Future<void> _submit() => _perform(() async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(secret.text)) {
      throw const HongguoAccountFailure('请输入正确的验证码');
    }
    final current = _current();
    await service.loginPhone(current, code: secret.text, verify: _verify);
    secret.clear();
    if (mounted) Navigator.pop(context, true);
  });
  @override
  void dispose() {
    if (attempt != null) attempt!.cancelled = true;
    timer?.cancel();
    service.dispose();
    country.dispose();
    number.dispose();
    secret.clear();
    secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('手机号与验证码登录')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextField(
                        key: const Key('login-country'),
                        controller: country,
                        enabled: !busy,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: '区号',
                          prefixText: '+',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const Key('login-phone'),
                        controller: number,
                        enabled: !busy,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [
                          AutofillHints.telephoneNumberNational,
                        ],
                        decoration: const InputDecoration(labelText: '手机号'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('login-secret'),
                  controller: secret,
                  enabled: !busy,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(labelText: '短信验证码'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('phone-send-code'),
                    onPressed: busy || remaining > 0 ? null : _send,
                    child: Text(
                      remaining > 0 ? '${remaining}s 后重新获取' : '获取验证码',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://hongguoduanju.com/'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('红果官方网站'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(error!, key: const Key('phone-login-error')),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('phone-login-submit'),
                  onPressed: busy ? null : _submit,
                  child: Text(busy ? '正在处理' : '登录'),
                ),
                const SizedBox(height: 12),
                const Text('验证码仅由你点击后发送。糖葫芦 Haw 不保存验证码。'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
