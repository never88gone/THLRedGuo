import 'package:flutter/material.dart';

import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/remote/remote_widgets.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 首页短剧网格与分类列表视图
class HomeCatalogView extends StatelessWidget {
  const HomeCatalogView({
    super.key,
    required this.items,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.hideVip,
    required this.television,
    required this.scrollController,
    required this.supportsSourceManagement,
    required this.sourcesCount,
    required this.canLoadMore,
    required this.gridKey,
    required this.onRetryLoad,
    required this.onLoadMore,
    this.onPrefetch,
    required this.onRefresh,
    required this.onManageSources,
    required this.onSwipeCategory,
    required this.tileBuilder,
  });

  final List<Drama> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final bool hideVip;
  final bool television;
  final ScrollController scrollController;
  final bool supportsSourceManagement;
  final int sourcesCount;
  final bool canLoadMore;
  final String gridKey;
  final VoidCallback onRetryLoad;
  final VoidCallback onLoadMore;
  final VoidCallback? onPrefetch;
  final Future<void> Function() onRefresh;
  final VoidCallback onManageSources;
  final void Function(DragEndDetails)? onSwipeCategory;
  final Widget Function(
    Drama drama, {
    FocusNode? focusNode,
    VoidCallback? onFocus,
  })
  tileBuilder;

  Widget _paginationFooter(BuildContext context) {
    if (loadingMore) return const CircularProgressIndicator();
    if (error != null && hasMore) {
      return television
          ? RemoteButton(
              label: '重试加载',
              icon: Icons.refresh,
              onPressed: onLoadMore,
            )
          : TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.refresh),
              label: const Text('重试加载'),
            );
    }
    return Text(
      hasMore ? '继续下滑加载更多' : '已经看到这里的全部剧集',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        onPrefetch?.call();
        return false;
      },
      child: GestureDetector(
        onHorizontalDragEnd: television ? null : onSwipeCategory,
        child: loading && items.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 18),
                    Text('正在加载剧集'),
                  ],
                ),
              )
            : items.isEmpty && error != null
            ? StatusPanel(
                title: '暂时无法加载',
                message: error!,
                onRetry: onRetryLoad,
                secondaryAction: supportsSourceManagement
                    ? TextButton(
                        onPressed: onManageSources,
                        child: const Text('站源诊断'),
                      )
                    : null,
                icon: Icons.wifi_off_rounded,
              )
            : items.isEmpty
            ? StatusPanel(
                title: '没有找到匹配的短剧',
                message: hideVip
                    ? '可以换个搜索词，或显示 VIP 内容。'
                    : sourcesCount > 1
                    ? '可以换个搜索词或切换站源。'
                    : '可以切换分类或搜索短剧，或刷新后重试。',
                onRetry: onRetryLoad,
                action: '刷新',
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (television) {
                    final columns = ((constraints.maxWidth - 36) / 150)
                        .floor()
                        .clamp(1, 8);
                    final tileWidth =
                        (constraints.maxWidth - 36 - (columns - 1) * 14) /
                        columns;
                    return RemoteGrid(
                      key: ValueKey('tv-grid-$gridKey'),
                      itemKeys: items.map((item) => item.id).toList(),
                      columns: columns,
                      itemExtent:
                          DramaTile.extentFor(context, tileWidth - 14) + 14,
                      controller: scrollController,
                      footer: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                        child: Center(child: _paginationFooter(context)),
                      ),
                      padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
                      itemBuilder: (_, index, node, onFocus) => tileBuilder(
                        items[index],
                        focusNode: node,
                        onFocus: onFocus,
                      ),
                    );
                  }
                  final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
                  return RefreshIndicator(
                    onRefresh: onRefresh,
                    child: CustomScrollView(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(padding, 0, padding, 16),
                          sliver: SliverGrid(
                            gridDelegate: dramaGridDelegate(
                              context,
                              constraints.maxWidth - 2 * padding,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (_, index) => tileBuilder(items[index]),
                              childCount: items.length,
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Center(child: _paginationFooter(context)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
