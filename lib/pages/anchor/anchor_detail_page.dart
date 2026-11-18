import 'package:flutter/material.dart';
import '../../core/account/hongguo_account_service.dart';
import '../../core/account/hongguo_account_session.dart';
import '../../core/bridge/core_bridge.dart';
import '../../core/store/local_store.dart';
import '../../models/catalog/models.dart';
import '../../utils/theme/app_colors.dart';
import '../detail/detail_page.dart';

class AnchorDetailPage extends StatefulWidget {
  const AnchorDetailPage({
    super.key,
    required this.anchor,
    required this.repository,
    required this.store,
    this.initialDramas = const [],
    this.onOpenDrama,
    this.service,
    this.onFollowingChanged,
  });
  final Anchor anchor;
  final AppRepository repository;
  final LocalStore store;
  final List<Drama> initialDramas;
  final ValueChanged<Drama>? onOpenDrama;
  final HongguoAccountService? service;
  final VoidCallback? onFollowingChanged;
  @override
  State<AnchorDetailPage> createState() => _AnchorDetailPageState();
}

class _AnchorDetailPageState extends State<AnchorDetailPage> {
  late final service = widget.service ?? HongguoAccountService();
  Anchor? profile;
  String? error;
  bool loading = true, writing = false;
  List<Drama> works = const [];
  bool worksLoadingMore = false;
  bool worksHasMore = false;
  String worksCursor = '';
  int worksSource = 1506;
  int worksTab = 23;
  int generation = 0;
  late int revision;

  List<Drama> get displayDramas {
    final seen = <String>{};
    final list = <Drama>[];
    for (final d in [...works, ...widget.initialDramas]) {
      if (seen.add(d.id)) list.add(d);
    }
    return list;
  }
  bool get following => service.session.loggedIn
      ? profile?.officialFollowing == true
      : profile?.isFollowed == true;
  bool get canChangeFollowing =>
      profile != null &&
      !loading &&
      !writing &&
      (!service.session.loggedIn ||
          profile!.officialFollowing != null &&
              (following || profile!.canFollow));

  Anchor get localProfile => widget.anchor.copyWith(
    isFollowed: widget.store.isAnchorFollowed(widget.anchor.id),
    officialFollowing: widget.store.isAnchorFollowed(widget.anchor.id),
  );
  @override
  void initState() {
    super.initState();
    revision = service.session.revision;
    service.session.addListener(_accountChanged);
    profile = service.session.loggedIn ? widget.anchor : localProfile;
    loading = false;
    _load();
  }

  void _accountChanged() {
    if (revision == service.session.revision) return;
    revision = service.session.revision;
    generation++;
    if (mounted) {
      setState(() {
        profile = service.session.loggedIn ? null : localProfile;
        works = const [];
        worksHasMore = false;
        worksCursor = '';
        worksLoadingMore = false;
        error = null;
        writing = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (!service.session.loggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
      worksHasMore = false;
      worksCursor = '';
      worksLoadingMore = false;
    });
    try {
      final value = await service.creatorProfile(widget.anchor.id);
      if (!mounted || ticket != generation) return;
      List<Drama> fetchedWorks = works;
      var hasMore = false;
      var nextCursor = '';
      var source = 1506;
      var tab = 23;
      try {
        final page = await service.creatorWorks(value.id);
        if (mounted && ticket == generation) {
          fetchedWorks = page.items;
          hasMore = page.hasMore && page.nextCursor.isNotEmpty;
          nextCursor = page.nextCursor;
          source = page.commentSource;
          tab = page.tabType;
        }
      } catch (_) {}
      if (mounted && ticket == generation) {
        setState(() {
          profile = value;
          works = fetchedWorks;
          worksHasMore = hasMore;
          worksCursor = nextCursor;
          worksSource = source;
          worksTab = tab;
        });
      }
    } catch (issue) {
      if (mounted && ticket == generation) {
        setState(
          () => error = issue is HongguoAccountFailure
              ? issue.message
              : '主播资料获取失败，请重试',
        );
      }
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  Future<void> _loadMoreWorks() async {
    final current = profile;
    if (!service.session.loggedIn ||
        current == null ||
        !worksHasMore ||
        worksLoadingMore ||
        worksCursor.isEmpty) {
      return;
    }
    final ticket = generation;
    final cursor = worksCursor;
    setState(() => worksLoadingMore = true);
    try {
      final page = await service.creatorWorks(
        current.id,
        cursor: cursor,
        commentSource: worksSource,
        tabType: worksTab,
      );
      if (!mounted || ticket != generation) return;
      final seen = {for (final d in works) d.id};
      final merged = [...works];
      for (final item in page.items) {
        if (seen.add(item.id)) merged.add(item);
      }
      setState(() {
        works = merged;
        worksHasMore =
            page.hasMore &&
            page.nextCursor.isNotEmpty &&
            page.nextCursor != cursor;
        worksCursor = page.nextCursor;
      });
    } catch (_) {
    } finally {
      if (mounted && ticket == generation) {
        setState(() => worksLoadingMore = false);
      }
    }
  }

  Future<void> _follow() async {
    final current = profile;
    if (current == null || !canChangeFollowing) return;
    final official = service.session.loggedIn;
    final nextFollowing = !following;
    final ticket = ++generation;
    setState(() {
      writing = true;
      error = null;
      profile = current.copyWith(
        isFollowed: nextFollowing,
        officialFollowing: nextFollowing,
      );
    });
    try {
      final value = official
          ? await service.setProfileFollowing(current, nextFollowing)
          : profile!;
      if (!mounted || ticket != generation) return;
      setState(() => profile = value);
      await widget.store.setAnchorFollowed(value, nextFollowing);
      if (mounted && ticket == generation) widget.onFollowingChanged?.call();
    } catch (issue) {
      if (mounted && ticket == generation) {
        setState(() {
          profile = current;
          error = issue is HongguoAccountFailure ? issue.message : '官方账号关注同步失败';
        });
      }
    } finally {
      if (mounted && ticket == generation) setState(() => writing = false);
    }
  }

  @override
  void dispose() {
    generation++;
    service.session.removeListener(_accountChanged);
    if (widget.service == null) service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final value = profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(value?.name ?? '主播详情'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('anchor-refresh'),
            onPressed: loading || writing ? null : _load,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('anchor-detail'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (loading)
            const LinearProgressIndicator(key: ValueKey('anchor-loading')),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(error!, key: const ValueKey('anchor-error')),
                  TextButton(
                    key: const ValueKey('anchor-retry'),
                    onPressed: loading || writing ? null : _load,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (value != null) ...[
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;
                final isDark = theme.brightness == Brightness.dark;

                final avatarUri = Uri.tryParse(value.avatar);
                final hasAvatar =
                    !const bool.fromEnvironment('DISABLE_REMOTE_IMAGES') &&
                    avatarUri != null &&
                    (avatarUri.scheme == 'https' || avatarUri.scheme == 'http');
                final avatarImage = hasAvatar ? NetworkImage(value.avatar) : null;

                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0x14FFFFFF) : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0x1AFFFFFF) : scheme.outlineVariant,
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.hongguoRed.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: isDark ? const Color(0x1FFFFFFF) : scheme.surfaceContainerHigh,
                          foregroundImage: avatarImage,
                          onForegroundImageError: avatarImage == null
                              ? null
                              : (_, _) {},
                          child: Icon(
                            Icons.person_outline_rounded,
                            size: 30,
                            color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        value.name,
                        key: const ValueKey('anchor-name'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x0FFFFFFF) : scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (value.dramasCount != null)
                              Text(
                                '作品 ${value.dramasCount}',
                                key: const ValueKey('anchor-works-count'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                              ),
                            if (value.fansCount != null && value.fansCount! > 0) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  '·',
                                  style: TextStyle(
                                    color: isDark ? Colors.white38 : scheme.outline,
                                  ),
                                ),
                              ),
                              Text(
                                '粉丝 ${value.fansCount}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        value.bio.isEmpty ? '暂无简介' : value.bio,
                        key: const ValueKey('anchor-bio'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (service.session.loggedIn) ...[
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          key: ValueKey(
                            following
                                ? 'anchor-followed-btn'
                                : 'anchor-follow-btn',
                          ),
                          onPressed: canChangeFollowing ? _follow : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: following
                                ? (isDark ? const Color(0x1FFFFFFF) : scheme.surfaceContainerHighest)
                                : AppColors.hongguoRed,
                            foregroundColor: following
                                ? (isDark ? Colors.white70 : scheme.onSurfaceVariant)
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 32),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          icon: Icon(
                            following
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            size: 16,
                          ),
                          label: Text(
                            writing
                                ? '正在确认'
                                : following
                                ? '已关注'
                                : '关注',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            if (displayDramas.isNotEmpty) ...[
              Row(
                children: [
                  Container(
                    width: 3.5,
                    height: 15,
                    decoration: BoxDecoration(
                      color: AppColors.hongguoRed,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '短剧作品 (${displayDramas.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final drama in displayDramas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    key: ValueKey('anchor-drama-${drama.id}'),
                    color: isDark ? AppColors.darkCard : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DetailScreen(
                            drama: drama,
                            repository: widget.repository,
                            store: widget.store,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.hongguoRed.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.movie_outlined,
                                color: AppColors.hongguoRed,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.repository.catalogUpdates
                                        .current(drama)
                                        .title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    drama.episodes > 0
                                        ? (drama.displayCategory.isNotEmpty
                                            ? '${drama.displayCategory} · 共 ${drama.episodes} 集'
                                            : '共 ${drama.episodes} 集')
                                        : (drama.displayCategory.isNotEmpty
                                            ? drama.displayCategory
                                            : '点击查看剧集'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.play_circle_outline_rounded,
                              color: AppColors.hongguoRed,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (worksHasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: worksLoadingMore ? null : _loadMoreWorks,
                      child: Text(worksLoadingMore ? '正在加载更多...' : '加载更多作品'),
                    ),
                  ),
                ),
            ] else if (!loading)
              Text(
                '暂无可展示的关联短剧',
                key: const ValueKey('anchor-no-works'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
          ],
        ],
      ),
    );
  }
}
