import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/player/playback_lease.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/feed/feed_models.dart';

class VideoFeedController extends ChangeNotifier {
  VideoFeedController(this.repository, this.store);
  final AppRepository repository;
  final LocalStore store;
  final playback = PlaybackLeaseQueue();
  List<FeedItem> items = [];
  int index = 0;
  int _page = 0;
  bool active = false;
  bool loading = false;
  bool loadingMore = false;
  bool loadingDetail = false;
  bool hasMore = true;
  String? error;
  String? moreError;
  bool restartRequired = false;
  String? detailError;
  DramaDetail? detail;
  int _generation = 0;
  int _selection = 0;
  bool _disposed = false;
  bool _preparing = false;
  String _session = '';
  final _details = <String, DramaDetail>{};
  Timer? _selectionTimer;

  bool get allowed => !store.locked && store.allowsSource('hongguo');
  FeedItem? get current => index < items.length ? items[index] : null;

  void setActive(bool value) {
    if (_disposed || active == value) return;
    active = value;
    if (!active) {
      detail = null;
      loadingDetail = false;
    }
    _selection++;
    _selectionTimer?.cancel();
    notifyListeners();
    if (active && allowed) {
      if (items.isEmpty && !loading) {
        unawaited(refresh());
      } else {
        unawaited(prepare());
      }
    }
  }

  Future<void> refresh({bool preserveCurrent = false}) async {
    if (_disposed || !allowed) return;
    final generation = ++_generation;
    _selection++;
    final retainId = preserveCurrent ? current?.drama.id : null;
    final offset = _session.isEmpty && store.feedSeenIds.isEmpty
        ? 0
        : store.stepFeedOffset();
    _session = '${DateTime.now().microsecondsSinceEpoch}_$offset';
    _selectionTimer?.cancel();
    items = [];
    detail = null;
    index = _page = 0;
    _details.clear();
    loading = true;
    loadingMore = false;
    hasMore = true;
    error = moreError = detailError = null;
    restartRequired = false;
    notifyListeners();
    try {
      final result = await repository.videoFeed(page: 1, session: _session);
      if (_disposed || generation != _generation || !allowed) return;
      final filtered = _filterSeen(result.items, retainId: retainId);
      items = (filtered.isEmpty && !result.hasMore)
          ? _unique(result.items)
          : filtered;
      _page = result.page;
      hasMore = result.hasMore;
    } catch (failure) {
      if (!_disposed && generation == _generation) error = failure.toString();
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
        if (active) unawaited(prepare());
        if (active && hasMore && items.length < 3) {
          unawaited(loadMore(retainId: retainId));
        }
      }
    }
  }

  List<FeedItem> _filterSeen(Iterable<FeedItem> values, {String? retainId}) {
    final list = <FeedItem>[];
    final seen = <String>{};
    for (final value in values) {
      final id = value.drama.id;
      if (value.drama.source == 'hongguo' &&
          id.isNotEmpty &&
          !seen.contains(id) &&
          (!store.isFeedSeen(id) || id == retainId)) {
        seen.add(id);
        list.add(value);
      }
    }
    return list;
  }

  List<FeedItem> _unique(Iterable<FeedItem> values) => <String, FeedItem>{
    for (final value in values)
      if (value.drama.source == 'hongguo' && value.drama.id.isNotEmpty)
        value.drama.id: value,
  }.values.toList();

  Future<void> loadMore({String? retainId}) async {
    if (_disposed ||
        !active ||
        !allowed ||
        loading ||
        loadingMore ||
        !hasMore ||
        moreError != null) {
      return;
    }
    final generation = _generation;
    loadingMore = true;
    notifyListeners();
    try {
      final result = await repository.videoFeed(
        page: _page + 1,
        session: _session,
      );
      if (_disposed || generation != _generation || !allowed) return;
      final existingIds = items.map((e) => e.drama.id).toSet();
      final fresh = _filterSeen(
        result.items,
        retainId: retainId,
      ).where((e) => !existingIds.contains(e.drama.id)).toList();
      items = [...items, ...fresh];
      _page = result.page;
      hasMore = result.hasMore;
    } catch (failure) {
      if (!_disposed && generation == _generation) {
        moreError = failure.toString();
        restartRequired =
            failure is AppFailure &&
            {'CURSOR_EXPIRED', 'MISSING_CURSOR'}.contains(failure.code);
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        notifyListeners();
        if (active &&
            hasMore &&
            moreError == null &&
            items.length - index < 3) {
          unawaited(loadMore(retainId: retainId));
        }
      }
    }
  }

  Future<void> retryMore() async {
    if (restartRequired) {
      await refresh(preserveCurrent: true);
      return;
    }
    moreError = null;
    await loadMore();
  }

  void select(int value) {
    if (_disposed || value < 0 || value >= items.length) return;
    index = value;
    _selection++;
    detail = null;
    detailError = null;
    loadingDetail = true;
    _selectionTimer?.cancel();
    notifyListeners();
    _selectionTimer = Timer(
      const Duration(milliseconds: 160),
      () => unawaited(prepare()),
    );
    if (index >= items.length - 2) {
      if (hasMore) {
        unawaited(loadMore());
      } else {
        unawaited(nextBatch());
      }
    }
  }

  Future<void> nextBatch({String? retainId}) async {
    if (_disposed ||
        !active ||
        !allowed ||
        loading ||
        loadingMore ||
        moreError != null) {
      return;
    }
    final generation = _generation;
    loadingMore = true;
    notifyListeners();
    try {
      final offset = store.stepFeedOffset();
      final newSession = '${DateTime.now().microsecondsSinceEpoch}_$offset';
      final result = await repository.videoFeed(page: 1, session: newSession);
      if (_disposed || generation != _generation || !allowed) return;
      final existingIds = items.map((e) => e.drama.id).toSet();
      var fresh = _filterSeen(
        result.items,
        retainId: retainId,
      ).where((e) => !existingIds.contains(e.drama.id)).toList();
      if (fresh.isEmpty && result.items.isNotEmpty) {
        fresh = result.items
            .where((e) => !existingIds.contains(e.drama.id))
            .map((e) => FeedItem(drama: e.drama))
            .toList();
      }
      if (fresh.isNotEmpty) {
        items = [...items, ...fresh];
        _page = result.page;
        _session = newSession;
        hasMore = result.hasMore;
      }
    } catch (failure) {
      if (!_disposed && generation == _generation) {
        moreError = failure.toString();
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<void> prepare() async {
    if (_preparing || _disposed || !active || !allowed || current == null) {
      return;
    }
    _preparing = true;
    try {
      while (!_disposed && active && allowed && current != null) {
        final ticket = _selection;
        final target = current!;
        final epoch = store.profileEpoch;
        loadingDetail = true;
        detail = null;
        detailError = null;
        notifyListeners();
        await playback.idle;
        if (_disposed || !active || ticket != _selection) continue;
        try {
          final loaded =
              _details[target.drama.id] ??
              await repository.detail(target.drama);
          if (_disposed ||
              !active ||
              ticket != _selection ||
              store.profileEpoch != epoch) {
            continue;
          }
          if (loaded.episodes.isEmpty) {
            throw AppFailure('这部短剧暂未返回可播放集数，请重试或上滑换一部');
          }
          _details[target.drama.id] = loaded;
          while (_details.length > 3) {
            _details.remove(_details.keys.first);
          }
          detail = loaded;
          loadingDetail = false;
          notifyListeners();
          unawaited(store.markFeedSeen(target.drama.id));
          break;
        } catch (failure) {
          if (_disposed || !active || ticket != _selection) continue;
          detailError = failure.toString();
          loadingDetail = false;
          notifyListeners();
          break;
        }
      }
    } finally {
      _preparing = false;
    }
  }

  void switchSeason(DramaDetail next) {
    if (_disposed || current == null) return;
    items = [...items]..[index] = FeedItem(drama: next.drama);
    detail = next;
    _details[next.drama.id] = next;
    _selection++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _selection++;
    _selectionTimer?.cancel();
    super.dispose();
  }
}
