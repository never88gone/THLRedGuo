import 'package:flutter/foundation.dart';
import 'hongguo_account_session.dart';
import 'hongguo_collection_models.dart';

class HongguoCollectionController<T> extends ChangeNotifier {
  HongguoCollectionController({
    required this.session,
    required this.request,
    required this.keyOf,
  }) {
    _revision = session.revision;
    session.addListener(_accountChanged);
  }
  final HongguoAccountSession session;
  final Future<HongguoCollectionPage<T>> Function(int offset, int douyinOffset)
  request;
  final String Function(T) keyOf;
  List<T> items = [];
  bool loading = false, loaded = false, hasMore = true;
  String? error;
  int unsupportedCount = 0, _offset = 0, _douyinOffset = 0, _generation = 0;
  late int _revision;
  int _emptyPages = 0;
  bool _disposed = false;
  bool _retryRefresh = false;

  void _accountChanged() {
    if (_revision == session.revision) return;
    _revision = session.revision;
    _generation++;
    items = [];
    loading = false;
    loaded = false;
    hasMore = true;
    error = null;
    _offset = 0;
    _douyinOffset = 0;
    unsupportedCount = 0;
    _emptyPages = 0;
    _retryRefresh = false;
    notifyListeners();
  }

  Future<void> load({bool refresh = false}) async {
    refresh = refresh || _retryRefresh;
    if (_disposed ||
        !session.loggedIn ||
        loading ||
        (!refresh && loaded && !hasMore)) {
      return;
    }
    final generation = ++_generation, revision = session.revision;
    final offset = refresh ? 0 : _offset, douyin = refresh ? 0 : _douyinOffset;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await request(offset, douyin);
      if (_disposed ||
          generation != _generation ||
          revision != session.revision) {
        return;
      }
      if (page.hasMore &&
          (page.nextOffset == null ||
              page.nextOffset! < offset ||
              page.nextOffset == offset &&
                  page.followingDouyinOffset <= douyin)) {
        throw const HongguoAccountFailure('分页未返回新的位置，请刷新后重试', 'INVALID_CURSOR');
      }
      _retryRefresh = false;
      final merged = <String, T>{
        for (final item in refresh ? <T>[] : items) keyOf(item): item,
      };
      for (final item in page.items) {
        merged[keyOf(item)] = item;
      }
      final added = merged.length - (refresh ? 0 : items.length);
      items = merged.values.toList();
      loaded = true;
      hasMore = page.hasMore;
      _offset = page.nextOffset ?? offset;
      _douyinOffset = page.followingDouyinOffset;
      unsupportedCount =
          (refresh ? 0 : unsupportedCount) + page.unsupportedCount;
      _emptyPages = added == 0 ? (refresh ? 0 : _emptyPages) + 1 : 0;
      if (hasMore && _emptyPages >= 3) error = '连续多页暂无可展示内容，请稍后重试';
    } catch (issue) {
      if (!_disposed &&
          generation == _generation &&
          revision == session.revision) {
        _retryRefresh = refresh;
        error = issue is HongguoAccountFailure ? issue.message : '账号列表获取失败，请重试';
      }
    } finally {
      if (!_disposed &&
          generation == _generation &&
          revision == session.revision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    session.removeListener(_accountChanged);
    super.dispose();
  }
}
