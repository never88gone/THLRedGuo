import '../../core/account/hongguo_collection_models.dart';
import '../../core/account/hongguo_collection_controller.dart';
import '../../views/account/hongguo_collection_view.dart';
import 'dart:async';
import '../../core/account/hongguo_account_library.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../../utils/screen/app_layout.dart';
import '../../utils/theme/app_colors.dart';
import 'login_page.dart';
import 'account_pairing_page.dart';
import '../anchor/anchor_detail_page.dart';
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
    this.library,
  });
  final AppRepository repository;
  final LocalStore store;
  final Widget Function(bool) localLibraryBuilder;
  final ValueChanged<Drama> onOpen;
  final VoidCallback? onOpenSettings;
  final bool initialHistory;
  final HongguoAccountService? service;
  final HongguoAccountSession? session;
  final HongguoAccountLibrary? library;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final HongguoAccountSession account =
      widget.session ?? HongguoAccountSession.shared;
  late final HongguoAccountService service =
      widget.service ?? HongguoAccountService(session: account);
  HongguoAccountLibrary? get _sharedLibrary =>
      widget.library ??
      (widget.service == null && widget.session == null
          ? HongguoAccountLibrary.shared
          : null);
  late final liked = HongguoCollectionController<HongguoLikedVideo>(
    session: account,
    request: (offset, _) => service.likedVideos(offset: offset),
    keyOf: (row) => row.key,
  );
  late final anchors = HongguoCollectionController<Anchor>(
    session: account,
    request: (offset, douyin) =>
        service.followingCreators(offset: offset, douyinOffset: douyin),
    keyOf: (row) => row.id,
  );
  final lists = <bool, List<WatchEntry>>{};
  final errors = <bool, String>{};
  final loading = <bool>{};
  late bool history = widget.initialHistory;
  late int _accountTab = widget.initialHistory ? 1 : 0;
  int revision = -1;
  @override
  void initState() {
    super.initState();
    account.addListener(_accountChanged);
    widget.store.addListener(_storeChanged);
    _sharedLibrary?.addListener(_libraryChanged);
    _accountChanged();
  }

  void _storeChanged() {
    if (mounted) setState(() {});
  }

  void _libraryChanged() {
    final shared = _sharedLibrary;
    if (!mounted || !account.loggedIn || shared == null) return;
    setState(() {
      for (final tab in [true, false]) {
        if (shared.isLoaded(tab)) {
          lists[tab] = shared.entries(tab);
        } else {
          lists.remove(tab);
        }
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
      final shared = _sharedLibrary;
      final entries = shared != null
          ? await shared.load(tab, refresh: refresh)
          : await service.library(history: tab);
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


  @override
  void dispose() {
    account.removeListener(_accountChanged);
    widget.store.removeListener(_storeChanged);
    liked.dispose();
    anchors.dispose();
    _sharedLibrary?.removeListener(_libraryChanged);
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (account.loggedIn) {
      final avatar =
          !const bool.fromEnvironment('DISABLE_REMOTE_IMAGES') &&
              Uri.tryParse(account.avatar)?.scheme == 'https'
          ? NetworkImage(account.avatar)
          : null;
      final displayName = account.nickname.isNotEmpty ? account.nickname : '用户';
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : scheme.outlineVariant,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.hongguoRed.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: isDark ? const Color(0x1FFFFFFF) : scheme.surfaceContainerHigh,
                  foregroundImage: avatar,
                  onForegroundImageError: avatar == null ? null : (_, _) {},
                  child: Icon(
                    Icons.person,
                    size: 20,
                    color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.hongguoRed.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 4.5,
                            height: 4.5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF4CAF50),
                            ),
                          ),
                          const SizedBox(width: 3.5),
                          const Text(
                            '红果账号已同步',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.hongguoRed,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: const Key('hongguo-account-more-menu'),
                tooltip: '更多',
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
                ),
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
                          Text('扫码配对'),
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
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 10),
          InkWell(
            onTap: _login,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : scheme.outlineVariant,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0x1FFFFFFF) : scheme.surfaceContainerHigh,
                      border: Border.all(
                        color: isDark ? const Color(0x26FFFFFF) : scheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 20,
                      color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '点击登录红果账号',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '登录同步多端追剧与观看记录',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white38 : scheme.outline,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final isLogged = account.loggedIn;
    if (!isLogged && _accountTab >= 2) {
      _accountTab = 0;
    }
    final tabDefs = <(int, String)>[
      (0, '追剧'),
      (1, '历史记录'),
      if (isLogged) ...[
        (2, '点赞视频'),
        (3, '关注主播'),
      ],
    ];

    return SafeArea(
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 600;
                final Widget content;
                if (_accountTab == 0) {
                  content = account.loggedIn
                      ? _cloudLibrary(false)
                      : widget.localLibraryBuilder(false);
                } else if (_accountTab == 1) {
                  content = account.loggedIn
                      ? _cloudLibrary(true)
                      : widget.localLibraryBuilder(true);
                } else if (_accountTab == 2) {
                  content = _likedVideosView();
                } else {
                  content = _followedAnchorsView();
                }

                if (!wide) {
                  return Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x0FFFFFFF) : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? const Color(0x14FFFFFF) : scheme.outlineVariant,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: tabDefs.map((tab) {
                            final index = tab.$1;
                            final label = tab.$2;
                            final selected = _accountTab == index;
                            return Expanded(
                              child: InkWell(
                                key: ValueKey('account-tab-$index'),
                                borderRadius: BorderRadius.circular(19),
                                onTap: () {
                                  setState(() {
                                    _accountTab = index;
                                    if (index < 2) history = index == 1;
                                  });
                                  if (index == 0) _load(false);
                                  if (index == 1) _load(true);
                                  if (index == 2) liked.load();
                                  if (index == 3) anchors.load();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.hongguoRed.withValues(
                                            alpha: isDark ? 0.20 : 0.12,
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(19),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.hongguoRed.withValues(
                                              alpha: isDark ? 0.55 : 0.40,
                                            )
                                        : Colors.transparent,
                                      width: 0.8,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: selected ? 12.5 : 12,
                                      fontWeight: selected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: selected
                                          ? (isDark ? Colors.white : AppColors.hongguoRed)
                                          : (isDark
                                              ? const Color(0x99FFFFFF)
                                              : scheme.onSurfaceVariant),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
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
                        children: tabDefs.map((tab) {
                          final index = tab.$1;
                          final label = tab.$2;
                          final selected = _accountTab == index;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: InkWell(
                              key: ValueKey('account-tab-$index'),
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  _accountTab = index;
                                  if (index < 2) history = index == 1;
                                });
                                if (index == 0) _load(false);
                                if (index == 1) _load(true);
                                if (index == 2) liked.load();
                                if (index == 3) anchors.load();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.hongguoRed.withValues(
                                          alpha: isDark ? 0.18 : 0.12,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.hongguoRed.withValues(
                                            alpha: isDark ? 0.45 : 0.40,
                                          )
                                        : Colors.transparent,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.hongguoRed
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          1.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: selected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: selected
                                            ? (isDark ? Colors.white : AppColors.hongguoRed)
                                            : (isDark
                                                ? const Color(0x8AFFFFFF)
                                                : scheme.onSurfaceVariant),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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
  }

  Widget _likedVideosView() {
    return HongguoCollectionView<HongguoLikedVideo>(
      key: const ValueKey('official-liked'),
      controller: liked,
      name: 'liked',
      title: '红果账号 · 点赞视频',
      emptyMessage: '暂无点赞的视频',
      localItems: const [],
      itemKey: (row) => row.id,
      sliver: (context, rows) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            return SliverGrid(
              gridDelegate: compactDramaGridDelegate(
                context,
                constraints.crossAxisExtent,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final row = rows[index];
                final drama =
                    row.drama ??
                    Drama(
                      id: row.id,
                      source: 'hongguo',
                      sourceId: row.seriesId,
                      title: row.title,
                      cover: row.cover,
                      description: row.description,
                      episodes: row.episodes,
                    );
                return DramaTile(
                  key: ValueKey('account-liked-${row.key}'),
                  heroTag: 'account-liked-cover-${row.key}',
                  drama: drama,
                  repository: widget.repository,
                  subtitle: row.subtitle,
                  compact: true,
                  onTap: () => widget.onOpen(drama),
                );
              }, childCount: rows.length),
            );
          },
        ),
      ),
    );
  }

  Widget _followedAnchorsView() {
    return HongguoCollectionView<Anchor>(
      key: const ValueKey('official-anchors'),
      controller: anchors,
      name: 'anchors',
      title: '红果账号 · 关注主播',
      emptyMessage: '暂无关注的主播',
      localItems: const [],
      itemKey: (anchor) => anchor.id,
      sliver: (context, rows) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final anchor = rows[index];
              return Card(
                key: ValueKey('anchor-card-${anchor.id}'),
                margin: const EdgeInsets.only(bottom: 6),
                color: isDark ? AppColors.darkCard : scheme.surfaceContainerHighest,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isDark ? AppColors.darkBorder : scheme.outlineVariant,
                    width: 0.8,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  minLeadingWidth: 32,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.hongguoRed.withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.hongguoRed,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    anchor.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  subtitle: anchor.bio.isEmpty
                      ? null
                      : Text(
                          anchor.bio,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : scheme.outline,
                  ),
                  onTap: () async {
                    var changed = false;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AnchorDetailPage(
                          anchor: anchor,
                          repository: widget.repository,
                          store: widget.store,
                          onOpenDrama: widget.onOpen,
                          onFollowingChanged: () => changed = true,
                          service: service,
                        ),
                      ),
                    );
                    if (mounted && changed && account.loggedIn) {
                      await anchors.load(refresh: true);
                    }
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _cloudLibrary(bool tabHistory) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final entries = lists[tabHistory] ?? const <WatchEntry>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '红果账号 · ${tabHistory ? '历史记录' : '追剧'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                key: const Key('account-library-refresh'),
                tooltip: '刷新列表',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                onPressed: loading.contains(tabHistory)
                    ? null
                    : () => _load(tabHistory, refresh: true),
                icon: Icon(
                  Icons.refresh,
                  size: 18,
                  color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (loading.contains(tabHistory)) const LinearProgressIndicator(),
        if (errors[tabHistory] != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    errors[tabHistory]!,
                    key: const Key('account-library-error'),
                  ),
                ),
                TextButton(
                  onPressed: () => _load(tabHistory, refresh: true),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    loading.contains(tabHistory)
                        ? '正在获取账号列表'
                        : errors[tabHistory] != null
                        ? '暂时无法读取账号列表'
                        : tabHistory
                        ? '暂无观看记录'
                        : '暂无追剧记录',
                    key: const Key('account-library-state'),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding = constraints.maxWidth < 600
                        ? 12.0
                        : 16.0;
                    return GridView.builder(
                      key: ValueKey('account-library-$tabHistory'),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        4,
                        horizontalPadding,
                        16,
                      ),
                      gridDelegate: compactDramaGridDelegate(
                        context,
                        constraints.maxWidth - 2 * horizontalPadding,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (_, index) {
                        final entry = entries[index];
                        return DramaTile(
                          key: ValueKey('account-card-${entry.drama.id}'),
                          drama: entry.drama,
                          repository: widget.repository,
                          compact: true,
                          onTap: () => widget.onOpen(entry.drama),
                          subtitle: tabHistory
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
