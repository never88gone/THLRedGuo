import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/account/hongguo_account_session.dart';
import '../../utils/screen/app_layout.dart';
import 'phone_login_page.dart';
import 'qr_login_page.dart';
import 'account_pairing_page.dart';

class HongguoLoginScreen extends StatelessWidget {
  const HongguoLoginScreen({super.key});
  Future<void> _open(BuildContext context, Widget page) async {
    final completed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => page));
    if (completed == true &&
        context.mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        HongguoAccountSession.shared.loggedIn) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile =
        (Platform.isIOS || Platform.isAndroid) &&
        !AppLayout.isTelevision(context);
    return Scaffold(
      appBar: AppBar(title: const Text('登录红果账号')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ListTile(
                  key: const Key('hongguo-login-sms'),
                  leading: const Icon(Icons.sms_outlined),
                  title: const Text('手机号与验证码'),
                  onTap: () => _open(context, const HongguoPhoneLoginScreen()),
                ),
                ListTile(
                  key: const Key('hongguo-login-qr'),
                  leading: const Icon(Icons.qr_code),
                  title: const Text('红果 App 扫码'),
                  subtitle: mobile
                      ? const Text('可保存二维码，在红果 App 的扫一扫中从相册选择')
                      : const Text('使用手机红果 App 扫码并确认'),
                  onTap: () => _open(context, const HongguoQrLoginScreen()),
                ),
                if (!mobile)
                  ListTile(
                    key: const Key('hongguo-login-haw-pair'),
                    leading: const Icon(Icons.phonelink_lock),
                    title: const Text('手机糖葫芦 Haw 扫码'),
                    subtitle: const Text('同一局域网，手机确认后加密传递当前账号'),
                    onTap: () => _open(
                      context,
                      AccountPairingReceiveScreen(
                        deviceName: Platform.localHostname,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
