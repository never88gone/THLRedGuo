import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/catalog/catalog_filters.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/pages/detail/detail_page.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/models/ranking/ranking_models.dart';
import 'package:THLRedLook/views/common/widgets.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.initialGroup,
  });
  final AppRepository repository;
  final LocalStore store;
  final String initialGroup;

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  final _scroll = ScrollController();
  List<RankingBoard> _boards = [];
  RankingBoard? _board;
  List<RankingItem> _items = [];
  bool _loading = true;
  bool _more = false;
  bool _hasMore = false;
  bool _failedMore = false;
  int _page = 1;
  int _generation = 0;
  String? _error;
  String _updated = '';
  bool? _waterfallMode;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    _initialize();
  }

  @override
  void dispose() {
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    _generation++;
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_hasMore || _loading || _more || !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final threshold = (position.viewportDimension * 1.2).clamp(260.0, 720.0);
    if (position.extentAfter <= threshold) {
      _load(more: true);
    }
  }

  void _metadataChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allBoards = (await widget.repository.rankingBoards())
          .where((board) => widget.store.allowsSource(board.source))
          .toList();
      if (!mounted || generation != _generation) return;

      final isAllSources = widget.initialGroup == 'all';
      final targetSource = widget.initialGroup.isNotEmpty && !isAllSources
          ? widget.initialGroup
          : widget.store.source;

      List<RankingBoard> boards;
      if (!isAllSources) {
        // 单源模式：榜单必须严格仅展示当前选中的数据源，彻底隔离未激活的数据源
        boards = allBoards
            .where((b) => b.source == targetSource || b.groupId == targetSource)
            .toList();
      } else {
        boards = allBoards;
      }

      setState(() {
        _boards = boards;
        _board =
            boards
                .where((board) => board.source == targetSource || board.groupId == targetSource)
                .firstOrNull ??
            boards.firstOrNull;
        _loading = false;
      });
      if (_board != null) await _load();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _load({bool more = false, bool force = false}) async {
    final board = _board;
    if (board == null || more && (_loading || _more || !_hasMore)) return;
    final generation = ++_generation;
    setState(() {
      _loading = !more;
      _more = more;
      _error = null;
      _failedMore = false;
    });
    try {
      final result = await widget.repository.rankings(
        board.id,
        page: more ? _page + 1 : 1,
        force: force,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (!more) {
          final seen = <String>{};
          final list = <RankingItem>[];
          for (final item in result.items) {
            if (seen.add(item.drama.id)) {
              final rank = list.length + 1;
              list.add(RankingItem(rank, item.drama, metric: item.metric));
            }
          }
          _items = list;
        } else {
          final existing = List<RankingItem>.from(_items);
          final seen = existing.map((e) => e.drama.id).toSet();
          for (final item in result.items) {
            if (seen.add(item.drama.id)) {
              final rank = existing.length + 1;
              existing.add(RankingItem(rank, item.drama, metric: item.metric));
            }
          }
          _items = existing;
        }
        _page = result.page;
        _hasMore = result.hasMore;
        _updated = result.updatedText;
        _error = result.warning.isEmpty ? null : result.warning;
        _loading = false;
        _more = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _failedMore = more;
          _loading = false;
          _more = false;
        });
      }
    }
  }

  void _select(RankingBoard board) {
    if (_board?.id == board.id) return;
    setState(() {
      _board = board;
      _items = [];
      _updated = '';
      _page = 1;
      _hasMore = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = SourceGroup.fromSources(
      _boards.map((board) => SourceSite.byId(board.source)).toSet(),
    );
    final boards = _boards
        .where((board) => board.groupId == _board?.groupId)
        .toList();
    final items = _items
        .map(
          (item) => RankingItem(
            item.rank,
            widget.repository.catalogUpdates.current(item.drama),
            metric: item.metric,
          ),
        )
        .where(
          (item) =>
              widget.store.allowsSource(item.drama.source) &&
              !(widget.store.hideVip && item.drama.vip),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<SourceGroup>(
          tooltip: '切换榜单站源',
          enabled: groups.length > 1,
          onSelected: (group) =>
              _select(_boards.firstWhere((board) => board.groupId == group.id)),
          itemBuilder: (_) => [
            for (final group in groups)
              PopupMenuItem(value: group, child: Text(group.name)),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _board == null
                    ? '榜单'
                    : '${SourceSite.byId(_board!.source).groupName}榜单',
              ),
              if (groups.length > 1) const Icon(Icons.expand_more_rounded),
            ],
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('toggle-ranking-view-mode'),
            tooltip: (_waterfallMode ?? (MediaQuery.sizeOf(context).width >= 600))
                ? '切换为列表视图'
                : '切换为瀑布流视图',
            icon: Icon(
              (_waterfallMode ?? (MediaQuery.sizeOf(context).width >= 600))
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed: () {
              final current =
                  _waterfallMode ?? (MediaQuery.sizeOf(context).width >= 600);
              setState(() => _waterfallMode = !current);
            },
          ),
          RefreshAction(
            loading: _loading || _more,
            tooltip: '更新榜单',
            onPressed: _board == null ? _initialize : () => _load(force: true),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (boards.isNotEmpty)
              CatalogFilters(
                key: ValueKey('ranking-boards-${_board!.groupId}'),
                categories: [
                  for (final board in boards)
                    CatalogCategory(board.id, board.name),
                ],
                category: _board!.id,
                onCategory: (id) =>
                    _select(boards.firstWhere((board) => board.id == id)),
                onRetry: () => _load(force: true),
              ),
            if (_board != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    [
                      _board!.description,
                      if (_updated.isNotEmpty) _updated,
                    ].join(' '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            if (_loading && items.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
            if (_error != null && items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loading || _more
                          ? null
                          : () => _load(more: _failedMore, force: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading && items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            '正在获取热播短剧榜单...',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _board?.source == 'hongguo'
                                ? '正在连接榜单服务，数据未完整返回时会自动重试'
                                : '正在同步最新榜单排行，请稍候片刻',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : items.isEmpty
                  ? StatusPanel(
                      title: _error == null ? '暂无榜单内容' : '榜单暂时无法加载',
                      message: _error ?? '当前站源暂无可显示的榜单。',
                      onRetry: _board == null
                          ? _initialize
                          : () => _load(force: true),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final isWide = width >= 600;
                        final isWaterfall = _waterfallMode ?? isWide;
                        if (isWaterfall) {
                          return _buildWaterfallView(context, items, width);
                        } else {
                          return _buildListView(context, items, width);
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterfallView(
    BuildContext context,
    List<RankingItem> items,
    double width,
  ) {
    final padding = width < 600 ? 12.0 : 20.0;
    final contentWidth = width - 2 * padding;
    final columns = width < 480
        ? 3
        : width < 720
        ? 4
        : width < 1000
        ? 5
        : width < 1300
        ? 6
        : (width / 180).floor().clamp(6, 9);
    final spacing = width < 600 ? 10.0 : 16.0;
    final itemWidth = (contentWidth - (columns - 1) * spacing) / columns;
    final coverHeight = itemWidth * 1.38;
    final itemHeight = coverHeight + 66.0;

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        key: ValueKey('ranking-waterfall-${_board!.id}'),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding, 8, padding, 16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 18,
                crossAxisSpacing: spacing,
                mainAxisExtent: itemHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = items[index];
                  return _buildRankingWaterfallCard(
                    context,
                    item,
                    itemWidth,
                    coverHeight,
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Center(
                child: _more
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    : _hasMore
                    ? OutlinedButton(
                        onPressed: () => _load(more: true),
                        child: const Text('加载更多'),
                      )
                    : const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('已显示全部榜单'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingWaterfallCard(
    BuildContext context,
    RankingItem item,
    double itemWidth,
    double coverHeight,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (badgeBg, badgeTextColor, badgeLabel) = switch (item.rank) {
      1 => (
        const LinearGradient(
          colors: [Color(0xFFFF3366), Color(0xFFFF5E3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        Colors.white,
        'TOP 1',
      ),
      2 => (
        const LinearGradient(
          colors: [Color(0xFFFF8C00), Color(0xFFFFA500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        Colors.white,
        'TOP 2',
      ),
      3 => (
        const LinearGradient(
          colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        Colors.white,
        'TOP 3',
      ),
      _ => (
        LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.85),
          ],
        ),
        Colors.white.withValues(alpha: 0.95),
        '#${item.rank}',
      ),
    };

    return Card(
      key: ValueKey('rank-${item.rank}-${item.drama.id}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onFocusChange: (focused) {
          if (focused) {
            Scrollable.ensureVisible(context, alignment: 0.4);
          }
        },
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => DetailScreen(
              drama: item.drama,
              repository: widget.repository,
              store: widget.store,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: itemWidth,
              height: coverHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DramaCover(
                      drama: item.drama,
                      repository: widget.repository,
                      radius: 8,
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          color: badgeTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.drama.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                if (item.metric.isNotEmpty) ...[
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 13,
                    color: AppColors.hongguoRed,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      item.metric,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.hongguoRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else if (item.drama.category.isNotEmpty) ...[
                  Expanded(
                    child: Text(
                      item.drama.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.whiteWithAlpha(0.6)
                            : AppColors.greyDark,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(
    BuildContext context,
    List<RankingItem> items,
    double width,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: ListView.builder(
            key: ValueKey('ranking-list-${_board!.id}'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == items.length) {
                return Center(
                  child: _more
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        )
                      : _hasMore
                      ? OutlinedButton(
                          onPressed: () => _load(more: true),
                          child: const Text('加载更多'),
                        )
                      : const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('已显示全部榜单'),
                        ),
                );
              }
              final item = items[index];
              return Card(
                key: ValueKey('rank-${item.rank}-${item.drama.id}'),
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: InkWell(
                  key: ValueKey('rank-${item.rank}-${item.drama.id}-tap'),
                  borderRadius: BorderRadius.circular(12),
                  onFocusChange: (focused) {
                    if (focused) {
                      Scrollable.ensureVisible(context, alignment: .4);
                    }
                  },
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(
                        drama: item.drama,
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${item.rank}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: item.rank <= 3
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 72,
                          height: 108,
                          child: DramaCover(
                            drama: item.drama,
                            repository: widget.repository,
                            radius: 8,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.drama.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (item.drama.category.isNotEmpty)
                                Text(
                                  item.drama.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (item.metric.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.local_fire_department_rounded,
                                        size: 14,
                                        color: AppColors.hongguoRed,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        item.metric,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.hongguoRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
