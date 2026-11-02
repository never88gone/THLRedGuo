import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/account/hongguo_account_session.dart';
import '../../core/account/hongguo_account_service.dart';
import '../../core/bridge/core_bridge.dart';
import '../../core/store/local_store.dart';
import '../../models/catalog/models.dart';
import '../../views/common/widgets.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.localLibraryBuilder,
    required this.onOpen,
    required this.onOpenSettings,
    this.initialHistory = true,
  });
  final AppRepository repository;
  final LocalStore store;
  final Widget Function(bool) localLibraryBuilder;
  final ValueChanged<Drama> onOpen;
  final VoidCallback onOpenSettings;
  final bool initialHistory;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final account = HongguoAccountSession.shared;
  final service = HongguoAccountService();
  final lists = <bool, List<WatchEntry>>{};
  final errors = <bool, String>{};
  final loading = <bool>{};
  late bool history = widget.initialHistory;
  int revision = -1;
  @override
  void initState() {
    super.initState();
    account.addListener(_accountChanged);
    _accountChanged();
  }

  void _accountChanged() {
    if (revision != account.revision) {
      revision = account.revision;
      lists.clear();
      errors.clear();
      loading.clear();
      if (account.loggedIn) unawaited(_verifyAndLoad());
    }
    if (mounted) setState(() {});
  }

  Future<void> _verifyAndLoad() async {
    final owner = revision;
    try {
      await service.verify();
    } catch (_) {}
    if (mounted && owner == revision) await _load(history);
  }

  Future<void> _load(bool tab, {bool refresh = false}) async {
    if (!account.loggedIn ||
        loading.contains(tab) ||
        !refresh && lists.containsKey(tab)) {
      return;
    }
    final owner = revision;
    setState(() {
      loading.add(tab);
      errors.remove(tab);
    });
    try {
      final entries = await service.library(history: tab);
      if (!mounted || owner != account.revision) return;
      setState(() => lists[tab] = entries);
    } catch (_) {
      if (mounted && owner == account.revision) {
        setState(() => errors[tab] = '账号列表获取失败，请重试');
      }
    } finally {
      if (mounted && owner == account.revision) {
        setState(() => loading.remove(tab));
      }
    }
  }

  void _select(bool value) {
    setState(() => history = value);
    if (account.loggedIn) unawaited(_load(value));
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    service.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const HongguoQrLoginScreen()),
    );
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前会话已退出，安全存储清理失败，请重试')));
      }
    }
  }

  Widget _accountButton() {
    if (!account.loggedIn) {
      return TextButton.icon(
        key: const Key('hongguo-account-login'),
        onPressed: _login,
        icon: const Icon(Icons.person_outline),
        label: const Text('登录'),
      );
    }
    final avatar =
        !const bool.fromEnvironment('DISABLE_REMOTE_IMAGES') &&
            Uri.tryParse(account.avatar)?.scheme == 'https'
        ? NetworkImage(account.avatar)
        : null;
    return PopupMenuButton<String>(
      key: const Key('hongguo-account-menu'),
      tooltip: '账号菜单',
      onSelected: (_) => _logout(),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'logout', child: Text('退出登录')),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              foregroundImage: avatar,
              onForegroundImageError: avatar == null ? null : (_, _) {},
              child: const Icon(Icons.person),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                account.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('我的', style: Theme.of(context).textTheme.headlineSmall),
              IconButton(
                key: const Key('my-settings'),
                tooltip: '设置',
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              const Spacer(),
              Flexible(child: _accountButton()),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 600;
              final tabs = [
                for (final value in [false, true])
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextButton.icon(
                      key: ValueKey(value ? 'my-history' : 'my-follows'),
                      onPressed: () => _select(value),
                      style: TextButton.styleFrom(
                        backgroundColor: history == value
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : null,
                      ),
                      icon: Icon(value ? Icons.history : Icons.bookmark_border),
                      label: Text(value ? '历史记录' : '追剧'),
                    ),
                  ),
              ];
              final content = account.loggedIn
                  ? _cloudLibrary()
                  : widget.localLibraryBuilder(history);
              if (!wide) {
                return Column(
                  children: [
                    Row(children: tabs),
                    Expanded(child: content),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 180,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: tabs,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
  Widget _cloudLibrary() {
    final entries = lists[history] ?? const <WatchEntry>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: Text('红果账号 · ${history ? '历史记录' : '追剧'}')),
              IconButton(
                key: const Key('account-library-refresh'),
                tooltip: '刷新列表',
                onPressed: loading.contains(history)
                    ? null
                    : () => _load(history, refresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (loading.contains(history)) const LinearProgressIndicator(),
        if (errors[history] != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    errors[history]!,
                    key: const Key('account-library-error'),
                  ),
                ),
                TextButton(
                  onPressed: () => _load(history, refresh: true),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    loading.contains(history)
                        ? '正在获取账号列表'
                        : errors[history] != null
                        ? '暂时无法读取账号列表'
                        : history
                        ? '暂无观看记录'
                        : '暂无追剧记录',
                    key: const Key('account-library-state'),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 170).floor().clamp(
                      2,
                      8,
                    );
                    final width =
                        (constraints.maxWidth - 32 - (columns - 1) * 12) /
                        columns;
                    return GridView.builder(
                      key: ValueKey('account-library-$history'),
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 12,
                        mainAxisExtent: DramaTile.extentFor(context, width),
                      ),
                      itemCount: entries.length,
                      itemBuilder: (_, index) {
                        final entry = entries[index];
                        return DramaTile(
                          key: ValueKey('account-card-${entry.drama.id}'),
                          drama: entry.drama,
                          repository: widget.repository,
                          onTap: () => widget.onOpen(entry.drama),
                          subtitle: history
                              ? '第 ${entry.episode} 集 · ${formatPosition(entry.position)}'
                              : '账号追剧',
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
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
