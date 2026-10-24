import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:THLRedLook/core/feed/video_feed_controller.dart';
import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/pages/player/player_page.dart';
import 'package:THLRedLook/utils/navigation/app_route_observer.dart';
import 'package:THLRedLook/views/common/widgets.dart';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({
    super.key,
    required this.controller,
    required this.active,
  });
  final VideoFeedController controller;
  final bool active;

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen>
    with RouteAware, WidgetsBindingObserver {
  final _pages = PageController(keepPage: false);
  PageRoute<dynamic>? _route;
  bool _covered = false;
  bool _opening = false;
  bool _foreground = true;
  VideoFeedController get feed => widget.controller;

  void _syncActive() =>
      feed.setActive(widget.active && !_covered && !_opening && _foreground);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _syncActive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _syncActive();
  }

  @override
  void didUpdateWidget(covariant VideoFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncActive();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _covered = true;
    _syncActive();
  }

  @override
  void didPopNext() {
    _covered = false;
    _syncActive();
  }

  Future<void> _openDetail() async {
    final drama = feed.detail?.drama ?? feed.current?.drama;
    if (_opening || drama == null) return;
    _opening = true;
    _syncActive();
    await feed.playback.idle;
    if (!mounted) return;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DetailScreen(
            drama: drama,
            repository: feed.repository,
            store: feed.store,
          ),
        ),
      );
    } finally {
      if (mounted) {
        _opening = false;
        _syncActive();
      }
    }
  }

  Future<void> _move(int direction) async {
    var target = feed.index + direction;
    if (target >= feed.items.length) {
      if (feed.hasMore) {
        await feed.loadMore();
      } else {
        await feed.nextBatch();
      }
    }
    if (!mounted ||
        !_pages.hasClients ||
        target < 0 ||
        target >= feed.items.length) {
      return;
    }
    await _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _refresh() {
    if (_pages.hasClients) _pages.jumpToPage(0);
    unawaited(feed.refresh());
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    feed.setActive(false);
    _pages.dispose();
    super.dispose();
  }

  Widget _page(int index) {
    final current = index == feed.index;
    final detail = current ? feed.detail : null;
    if (current && feed.active && detail != null && !feed.loadingDetail) {
      final watched = feed.store.watched(detail.drama.id);
      final initial = watched == null
          ? (feed.items[index].episode - 1).clamp(0, detail.episodes.length - 1)
          : resumeEpisodeIndex(detail.episodes, watched);
      return PlayerScreen(
        key: ValueKey('feed-player-${detail.drama.id}'),
        detail: detail,
        initialIndex: initial,
        initialPosition:
            watched?.position.toDouble() ?? feed.items[index].position,
        repository: feed.repository,
        store: feed.store,
        feed: true,
        playbackQueue: feed.playback,
        onOpenDetail: () => unawaited(_openDetail()),
        onSeasonChanged: feed.switchSeason,
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: !current || !feed.active
            ? Text(
                feed.items[index].drama.title,
                style: const TextStyle(color: Colors.white54),
              )
            : feed.detailError != null
            ? StatusPanel(
                title: '这部暂时无法播放',
                message: feed.detailError!,
                onRetry: () => unawaited(feed.prepare()),
              )
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: feed,
    builder: (context, _) => Theme(
      data: ThemeData.dark(),
      child: ColoredBox(
        key: const ValueKey('video-feed'),
        color: Colors.black,
        child: !feed.allowed
            ? const StatusPanel(title: '当前用户未开放精选短剧', message: '可在设置中调整站源权限。')
            : feed.items.isEmpty
            ? feed.loading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white70),
                          SizedBox(height: 16),
                          Text(
                            '正在加载精彩短剧视频...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : StatusPanel(
                      title: feed.error == null ? '暂无推荐' : '推荐暂时无法加载',
                      message: feed.error ?? '刷新后获取新的推荐',
                      onRetry: _refresh,
                    )
            : CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                      unawaited(_move(1)),
                  const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                      unawaited(_move(-1)),
                },
                child: Stack(
                  children: [
                    PageView.builder(
                      key: const ValueKey('feed-pager'),
                      controller: _pages,
                      scrollDirection: Axis.vertical,
                      itemCount: feed.items.length,
                      onPageChanged: feed.select,
                      itemBuilder: (context, index) => _page(index),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '推荐',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    '上滑换剧',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('feed-refresh'),
                                  tooltip: '刷新推荐',
                                  onPressed: feed.loading ? null : _refresh,
                                  color: Colors.white,
                                  icon: const Icon(Icons.refresh),
                                ),
                                IconButton(
                                  key: const ValueKey('feed-previous'),
                                  tooltip: '上一部',
                                  onPressed: feed.index > 0
                                      ? () => unawaited(_move(-1))
                                      : null,
                                  color: Colors.white,
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                ),
                                IconButton(
                                  key: const ValueKey('feed-next'),
                                  tooltip: '下一部',
                                  onPressed: () => unawaited(_move(1)),
                                  color: Colors.white,
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ],
                            ),
                            if (feed.loadingMore)
                              const LinearProgressIndicator(minHeight: 2),
                            if (feed.moreError != null)
                              Material(
                                color: const Color(0xD9222222),
                                borderRadius: BorderRadius.circular(8),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        '更多推荐暂时加载失败',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    TextButton(
                                      key: const ValueKey('feed-retry-more'),
                                      onPressed: () =>
                                          unawaited(feed.retryMore()),
                                      child: Text(
                                        feed.restartRequired ? '刷新' : '重试',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
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
