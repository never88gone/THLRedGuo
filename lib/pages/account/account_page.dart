import 'dart:async';
import '../../core/account/hongguo_account_library.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../../utils/screen/app_layout.dart';
import '../../utils/theme/app_colors.dart';
import 'login_page.dart';
import 'account_pairing_page.dart';
export 'qr_login_page.dart';
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
    this.onOpenSettings,
    this.initialHistory = true,
    this.service,
    this.session,
  });
  final AppRepository repository;
  final LocalStore store;
  final Widget Function(bool) localLibraryBuilder;
  final ValueChanged<Drama> onOpen;
  final VoidCallback? onOpenSettings;
  final bool initialHistory;
  final HongguoAccountService? service;
  final HongguoAccountSession? session;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final HongguoAccountSession account =
      widget.session ?? HongguoAccountSession.shared;
  late final HongguoAccountService service =
      widget.service ?? HongguoAccountService();
  final lists = <bool, List<WatchEntry>>{};
  final errors = <bool, String>{};
  final loading = <bool>{};
  late bool history = widget.initialHistory;
  int revision = -1;
  @override
  void initState() {
    super.initState();
    account.addListener(_accountChanged);
    if (widget.service == null && widget.session == null) {
      HongguoAccountLibrary.shared.addListener(_libraryChanged);
    }
    _accountChanged();
  }

  void _libraryChanged() {
    if (!mounted || !account.loggedIn) return;
    setState(() {
      for (final tab in [true, false]) {
        lists[tab] = HongguoAccountLibrary.shared.entries(tab);
      }
    });
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
      final entries = widget.service != null || widget.session != null
          ? await service.library(history: tab)
          : await HongguoAccountLibrary.shared.load(tab, refresh: refresh);
      if (!mounted || owner != account.revision) return;
      setState(() => lists[tab] = entries);
    } catch (_) {
      if (mounted && owner == account.revision) {
        setState(() => errors[tab] = '账号列表获取失败，请重试');
      }
    } finally {
      if (mounted) {
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
    if (widget.service == null && widget.session == null) {
      HongguoAccountLibrary.shared.removeListener(_libraryChanged);
    }
    if (widget.service == null) {
      service.dispose();
    }
    super.dispose();
  }

  Future<void> _login() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('账号登录提示'),
        content: const Text(
          '登录后将使用短剧平台的接口数据同步追剧与观看记录，原有本地与 iCloud 记录会保留，退出账号后继续使用。\n\n是否确认登录？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.hongguoRed,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const HongguoLoginScreen()));
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

  Widget _buildHeader(BuildContext context) {
    if (account.loggedIn) {
      final avatar =
          !const bool.fromEnvironment('DISABLE_REMOTE_IMAGES') &&
              Uri.tryParse(account.avatar)?.scheme == 'https'
          ? NetworkImage(account.avatar)
          : null;
      final displayName = account.nickname.isNotEmpty ? account.nickname : '用户';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              foregroundImage: avatar,
              onForegroundImageError: avatar == null ? null : (_, _) {},
              child: const Icon(Icons.person, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            PopupMenuButton<String>(
              key: const Key('hongguo-account-more-menu'),
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (action) {
                if (action == 'scan') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountPairingScanScreen(),
                    ),
                  );
                } else if (action == 'logout') {
                  _logout();
                }
              },
              itemBuilder: (_) => [
                if ((Platform.isIOS || Platform.isAndroid) &&
                    !AppLayout.isTelevision(context))
                  const PopupMenuItem(
                    value: 'scan',
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('扫码'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('退出登录'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(
            '我的',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          FilledButton.icon(
            key: const Key('hongguo-account-login'),
            onPressed: _login,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.hongguoRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: const Size(0, 36),
              shape: const StadiumBorder(),
              elevation: 0,
            ),
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text(
              '登录',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        _buildHeader(context),
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
