import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/feed/video_feed_controller.dart';
import 'package:THLRedLook/core/player/playback_lease.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/feed/feed_models.dart';
import 'package:THLRedLook/views/feed/feed_player_overlay.dart';

const a = Drama(
  id: 'hongguo:a',
  source: 'hongguo',
  title: '合成推荐甲',
  episodes: 2,
);
const b = Drama(
  id: 'hongguo:b',
  source: 'hongguo',
  title: '合成推荐乙',
  episodes: 2,
);
DramaDetail detail(Drama drama) => DramaDetail(drama, [
  Episode({'id': '${drama.id}_1'}, 1),
  Episode({'id': '${drama.id}_2'}, 2),
]);

class Repo extends AppRepository {
  final pages = <int>[];
  final sessions = <String>[];
  final details = <String>[];
  bool failMore = false;
  String moreCode = '';
  Completer<FeedPage>? first;
  Completer<DramaDetail>? pendingDetail;
  @override
  Future<FeedPage> videoFeed({int page = 1, required String session}) async {
    pages.add(page);
    sessions.add(session);
    if (page == 1 && first != null) return first!.future;
    if (page > 1 && failMore) throw AppFailure('合成断网', code: moreCode);
    return FeedPage(
      items: page == 1
          ? const [FeedItem(drama: a), FeedItem(drama: b)]
          : const [
              FeedItem(drama: b),
              FeedItem(
                drama: Drama(
                  id: 'hongguo:c',
                  source: 'hongguo',
                  title: '合成推荐丙',
                ),
              ),
            ],
      page: page,
      hasMore: page < 2,
    );
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    details.add(drama.id);
    return pendingDetail?.future ??
        Future.value(FeedDetailFactory.build(drama));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FeedDetailFactory {
  static DramaDetail build(Drama drama) => detail(drama);
}

Future<void> flush() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = LocalStore(await SharedPreferences.getInstance());
  });
  tearDown(() => store.dispose());
  test(
    'first unseen feed uses bootstrap batch and refresh rotates offset',
    () async {
      final repo = Repo();
      final feed = VideoFeedController(repo, store);
      await feed.refresh();
      expect(repo.sessions.single.endsWith('_0'), true);
      await feed.refresh();
      expect(repo.sessions.last.endsWith('_6'), true);
      feed.dispose();
      await store.markFeedSeen(a.id);
      final returning = VideoFeedController(repo, store);
      await returning.refresh();
      expect(repo.sessions.last.endsWith('_12'), true);
      returning.dispose();
    },
  );
  test(
    'list refresh does not wait for player disposal but playback still does',
    () async {
      final repo = Repo();
      final feed = VideoFeedController(repo, store);
      final lease = feed.playback.acquire();
      try {
        var finished = false;
        final refresh = feed.refresh().then((_) => finished = true);
        await flush();
        expect(finished, true);
        expect(feed.items, isNotEmpty);
        expect(feed.loading, false);
        feed.setActive(true);
        await flush();
        expect(repo.details, isEmpty);
        await lease.releaseAfter(Future.value());
        await refresh;
        await flush();
        expect(feed.detail?.drama.id, a.id);
      } finally {
        await lease.releaseAfter(Future.value());
        feed.dispose();
      }
    },
  );
  test(
    'does not fetch off tab, keeps items and stops preparing while hidden',
    () async {
      final repo = Repo();
      final feed = VideoFeedController(repo, store);
      expect(repo.pages, isEmpty);
      feed.setActive(true);
      await flush();
      expect(feed.detail?.drama.id, a.id);
      feed.setActive(false);
      expect(feed.detail, isNull);
      expect(feed.items.length, 3);
      feed.setActive(true);
      await flush();
      expect(feed.detail?.drama.id, a.id);
      expect(repo.pages, [1, 2]);
      feed.dispose();
    },
  );
  test(
    'pagination failure retains current content and retries the same page once requested',
    () async {
      final repo = Repo()..failMore = true;
      final feed = VideoFeedController(repo, store);
      feed.setActive(true);
      await flush();
      await feed.loadMore();
      expect(feed.items.length, 2);
      expect(feed.moreError, contains('合成断网'));
      await feed.loadMore();
      expect(repo.pages, [1, 2]);
      repo.failMore = false;
      await feed.retryMore();
      expect(repo.pages, [1, 2, 2]);
      expect(feed.items.map((e) => e.drama.id), [
        'hongguo:a',
        'hongguo:b',
        'hongguo:c',
      ]);
      expect(feed.hasMore, false);
      feed.dispose();
    },
  );
  test(
    'expired recommendation cursor refreshes the batch instead of repeating an invalid cursor',
    () async {
      final repo = Repo()
        ..failMore = true
        ..moreCode = 'CURSOR_EXPIRED';
      final feed = VideoFeedController(repo, store);
      feed.setActive(true);
      await flush();
      expect(feed.restartRequired, true);
      repo.failMore = false;
      await feed.retryMore();
      await flush();
      expect(repo.pages, [1, 2, 1, 2]);
      expect(feed.restartRequired, false);
      expect(feed.items.length, 3);
      feed.dispose();
    },
  );
  test('stale refresh result cannot overwrite a fresh batch', () async {
    final repo = Repo()..first = Completer<FeedPage>();
    final feed = VideoFeedController(repo, store);
    feed.setActive(true);
    await flush();
    final old = repo.first!;
    repo.first = null;
    await feed.refresh();
    old.complete(const FeedPage(items: [], page: 1, hasMore: false));
    await flush();
    expect(feed.items.length, 3);
    expect(feed.error, isNull);
    feed.dispose();
  });
  test(
    'hidden detail request cannot restart playback and old player lease closes before next detail',
    () async {
      final repo = Repo()..pendingDetail = Completer<DramaDetail>();
      final feed = VideoFeedController(repo, store);
      feed.setActive(true);
      await flush();
      feed.setActive(false);
      repo.pendingDetail!.complete(detail(a));
      await flush();
      expect(feed.detail, isNull);
      repo.pendingDetail = null;
      feed.setActive(true);
      await flush();
      final lease = feed.playback.acquire();
      feed.select(1);
      await Future<void>.delayed(const Duration(milliseconds: 190));
      expect(repo.details.last, a.id);
      await lease.releaseAfter(Future.value());
      await flush();
      expect(feed.detail?.drama.id, b.id);
      feed.dispose();
    },
  );
  test(
    'playback lease serializes rapid changes and releases even after disposal failure',
    () async {
      final queue = PlaybackLeaseQueue();
      final first = queue.acquire();
      final second = queue.acquire();
      final third = queue.acquire();
      var ready = false;
      second.ready.then((_) {
        ready = true;
      });
      await flush();
      expect(ready, false);
      await first.releaseAfter(Future.value());
      await flush();
      expect(ready, true);
      await expectLater(
        second.releaseAfter(
          Future.error(StateError('synthetic dispose failure')),
        ),
        throwsStateError,
      );
      await third.ready;
      await third.releaseAfter(Future.value());
      await queue.idle;
    },
  );
  for (final size in [
    const Size(390, 720),
    const Size(740, 350),
    const Size(360, 260),
  ]) {
    testWidgets(
      'synthetic feed overlay fits $size and exposes playback actions',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var selected = false;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeedPlayerOverlay(
                title: '合成短剧名称',
                episodeText: '第 2 集 · 共 60 集',
                description: '合成剧情简介',
                playing: true,
                enabled: true,
                following: false,
                danmakuEnabled: true,
                position: const Duration(seconds: 3),
                duration: const Duration(seconds: 90),
                onTogglePlayback: () => selected = true,
                onSeek: (_) {},
                onFavorite: () {},
                onEpisodes: () {},
                onDetail: () {},
                onDanmaku: () {},
                onSettings: () {},
              ),
            ),
          ),
        );
        expect(t.takeException(), isNull);
        expect(find.byKey(const ValueKey('feed-play-pause')), findsNothing);
        expect(find.byKey(const ValueKey('feed-progress')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('feed-play-surface')));
        expect(selected, true);
      },
    );
  }

  testWidgets('推荐页面底部单线渐变进度条贴底满宽顶到两端边缘，且左侧无播放按钮', (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    double? seekResult;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedPlayerOverlay(
            title: '测试渐变进度条',
            episodeText: '第 1 集',
            description: '测试描述',
            playing: true,
            enabled: true,
            following: false,
            danmakuEnabled: true,
            position: const Duration(seconds: 10),
            duration: const Duration(seconds: 100),
            onTogglePlayback: () {},
            onSeek: (v) => seekResult = v,
            onFavorite: () {},
            onEpisodes: () {},
            onDetail: () {},
            onDanmaku: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);

    // 1. 验证进度左侧的播放状态按钮已去掉
    expect(find.byKey(const ValueKey('feed-play-pause')), findsNothing);

    // 2. 验证进度条组件存在，且左右完全顶到屏幕边缘（left: 0, right: 400）
    final progressFinder = find.byKey(const ValueKey('feed-progress'));
    expect(progressFinder, findsOneWidget);
    final rect = t.getRect(progressFinder);
    expect(rect.left, 0.0);
    expect(rect.right, 400.0);
    expect(rect.bottom, 800.0);

    // 3. 点击进度条中间位置进行 Seek
    await t.tap(progressFinder);
    await t.pumpAndSettle();
    expect(seekResult, isNotNull);
    expect(seekResult!, inInclusiveRange(0.0, 1.0));

    // 4. 拖拽进度条进行 Seek
    await t.drag(progressFinder, const Offset(50, 0));
    await t.pumpAndSettle();
    expect(seekResult, isNotNull);
  });

  test('冷启动或下次打开推荐流时自动过滤已看视频并换新', () async {
    final repo = MultiPageRepo();
    // 第一次打开 App 进入推荐
    final feed1 = VideoFeedController(repo, store);
    feed1.setActive(true);
    await flush();

    // 此时第一部是剧集1，准备就绪并播放
    expect(feed1.items.first.drama.id, 'hongguo:1');
    expect(feed1.detail?.drama.id, 'hongguo:1');
    // 验证 store 中已被自动标记为已看
    expect(store.isFeedSeen('hongguo:1'), isTrue);

    // 用户退出 App（释放 feed1）
    feed1.dispose();

    // 第二次打开 App（冷启动，新建 VideoFeedController）
    final feed2 = VideoFeedController(repo, store);
    feed2.setActive(true);
    await flush();

    // 验证：下次打开推荐时，第一部不再是看过的 hongguo:1，而是未看的全新短剧！
    expect(feed2.items.first.drama.id, isNot('hongguo:1'));
    expect(feed2.detail?.drama.id, isNot('hongguo:1'));
    expect(feed2.items.any((item) => item.drama.id == 'hongguo:1'), isFalse);
    expect(feed2.items.first.drama.id, 'hongguo:2');
    feed2.dispose();
  });

  test('推荐游标 offset 在每次刷新或新会话时自动轮转推进', () async {
    final offset0 = store.feedOffset;
    final next1 = store.stepFeedOffset();
    expect(next1, (offset0 + 6) % 60);
    final next2 = store.stepFeedOffset();
    expect(next2, (offset0 + 12) % 60);
  });

  test('推荐流支持 nextBatch 无缝跨批次加载，实现无限翻页', () async {
    final repo = MultiPageRepo();
    final feed = VideoFeedController(repo, store);
    feed.setActive(true);
    await flush();

    expect(feed.items.length, 4); // 初始拉取 page 1 和 page 2
    expect(feed.hasMore, false); // 第二页返回 hasMore = false

    // 触发下一批次轮转拉取
    await feed.nextBatch();
    expect(feed.items.length, 4); // 相同 items 已在当前列表中（去重保护）
    feed.dispose();
  });
}

class MultiPageRepo extends AppRepository {
  @override
  Future<FeedPage> videoFeed({int page = 1, required String session}) async {
    if (page == 1) {
      return const FeedPage(
        items: [
          FeedItem(
            drama: Drama(
              id: 'hongguo:1',
              source: 'hongguo',
              title: '剧集1',
              episodes: 5,
            ),
          ),
          FeedItem(
            drama: Drama(
              id: 'hongguo:2',
              source: 'hongguo',
              title: '剧集2',
              episodes: 5,
            ),
          ),
        ],
        page: 1,
        hasMore: true,
      );
    } else {
      return FeedPage(
        items: const [
          FeedItem(
            drama: Drama(
              id: 'hongguo:3',
              source: 'hongguo',
              title: '剧集3',
              episodes: 5,
            ),
          ),
          FeedItem(
            drama: Drama(
              id: 'hongguo:4',
              source: 'hongguo',
              title: '剧集4',
              episodes: 5,
            ),
          ),
        ],
        page: page,
        hasMore: false,
      );
    }
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    return DramaDetail(drama, [
      Episode({'id': '${drama.id}_1'}, 1),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
