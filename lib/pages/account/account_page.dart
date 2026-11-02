import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/account/hongguo_account_session.dart';
import '../../core/account/hongguo_account_service.dart';
import '../../core/bridge/core_bridge.dart';
import '../../core/store/local_store.dart';
import '../settings/settings_page.dart';
import '../downloads/downloads_page.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final account = HongguoAccountSession.shared;
  final service = HongguoAccountService();
  String? error;
  bool checking = false;
  @override
  void initState() {
    super.initState();
    if (account.loggedIn) unawaited(_verify());
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      checking = true;
      error = null;
    });
    try {
      await service.verify();
    } catch (_) {
      if (mounted) setState(() => error = '暂时无法确认账号，请稍后重试；本地资料已保留');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _login() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const HongguoQrLoginScreen()),
    );
    if (mounted) setState(() => error = null);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出红果账号？'),
        content: const Text('本机追剧、历史和播放进度会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await account.logout();
    } catch (_) {
      if (mounted) setState(() => error = '已退出当前会话，安全存储清理失败，请重试退出');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: account,
    builder: (context, _) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('我的', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.account_circle_outlined, size: 64),
                  const SizedBox(height: 12),
                  Text(
                    account.loggedIn ? account.nickname : '登录红果账号',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    account.loggedIn
                        ? checking
                              ? '正在确认登录状态'
                              : account.verified
                              ? '红果账号已登录'
                              : '登录状态待确认'
                        : '使用手机红果 App 扫码，在手机上确认登录',
                  ),
                  if (account.loggedIn)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '账号尾号：${account.id.length > 4 ? account.id.substring(account.id.length - 4) : account.id}',
                      ),
                    ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        key: const Key('hongguo-account-login'),
                        onPressed: _login,
                        icon: const Icon(Icons.qr_code),
                        label: Text(
                          account.loggedIn ? '重新扫码 / 切换账号' : '红果 App 扫码登录',
                        ),
                      ),
                      if (account.loggedIn)
                        OutlinedButton(
                          onPressed: checking ? null : _verify,
                          child: const Text('确认账号状态'),
                        ),
                      if (account.loggedIn)
                        TextButton(
                          onPressed: _logout,
                          child: const Text('退出登录'),
                        ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(error!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text('本地用户：${widget.store.profile.name}'),
            subtitle: const Text('红果账号与当前本地用户绑定，收藏、历史和进度继续保留'),
          ),
          if (widget.store.canDownload)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('下载管理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DownloadsScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('应用设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(
                  repository: widget.repository,
                  store: widget.store,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('本地追剧与最近观看可从主导航进入。官方账号收藏、历史、点赞和预约同步尚未接入。'),
          ),
        ],
      ),
    ),
  );
}

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
    if (remaining <= 0 && !current.confirmed) {
      timer?.cancel();
      current.cancelled = true;
      setState(() => error = '二维码已过期，请刷新');
      return;
    }
    if (!foreground || polling || remaining % 2 != 0 || failures >= 3) return;
    polling = true;
    try {
      final complete = await service.poll(current);
      if (!mounted || current != login) return;
      if (complete) {
        timer?.cancel();
        Navigator.of(context).pop();
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
                    child: Icon(Icons.qr_code_2, size: 100),
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
