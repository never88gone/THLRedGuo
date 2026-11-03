import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/account/hongguo_account_service.dart';
import '../../core/account/hongguo_account_session.dart';

class HongguoPhoneLoginScreen extends StatefulWidget {
  const HongguoPhoneLoginScreen({super.key, this.passwordMode = false});
  final bool passwordMode;
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
  late bool passwordMode = widget.passwordMode;
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
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = '登录请求暂时失败，请稍后再试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _send() => _perform(() async {
    final current = _current();
    final seconds = await service.sendPhoneCode(current);
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
    if (secret.text.isEmpty ||
        !passwordMode && !RegExp(r'^\d{4,8}$').hasMatch(secret.text)) {
      throw HongguoAccountFailure(passwordMode ? '请输入密码' : '请输入正确的验证码');
    }
    final current = _current();
    await service.loginPhone(
      current,
      code: passwordMode ? null : secret.text,
      password: passwordMode ? secret.text : null,
    );
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
    appBar: AppBar(title: Text(passwordMode ? '手机号与密码登录' : '手机号与验证码登录')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('验证码')),
                    ButtonSegment(value: true, label: Text('密码')),
                  ],
                  selected: {passwordMode},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() {
                          passwordMode = v.single;
                          secret.clear();
                          error = null;
                        }),
                ),
                const SizedBox(height: 24),
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
                  obscureText: passwordMode,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: passwordMode
                      ? TextInputType.visiblePassword
                      : TextInputType.number,
                  autofillHints: passwordMode
                      ? const [AutofillHints.password]
                      : const [AutofillHints.oneTimeCode],
                  decoration: InputDecoration(
                    labelText: passwordMode ? '密码' : '短信验证码',
                  ),
                ),
                if (!passwordMode)
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
                const Text('验证码仅由你点击后发送。糖葫芦 Haw 不保存密码或验证码。'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
