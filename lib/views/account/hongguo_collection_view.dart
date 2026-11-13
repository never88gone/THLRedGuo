import 'package:flutter/material.dart';
import '../../core/account/hongguo_collection_controller.dart';

class HongguoCollectionView<T> extends StatefulWidget {
  const HongguoCollectionView({
    super.key,
    required this.controller,
    required this.name,
    required this.title,
    required this.emptyMessage,
    required this.sliver,
  });
  final HongguoCollectionController<T> controller;
  final String name, title, emptyMessage;
  final Widget Function(BuildContext, List<T>) sliver;

  @override
  State<HongguoCollectionView<T>> createState() =>
      _HongguoCollectionViewState<T>();
}

class _HongguoCollectionViewState<T> extends State<HongguoCollectionView<T>> {
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    scroll.addListener(_nearEnd);
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.controller.loaded) widget.controller.load();
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nearEnd();
    });
  }

  void _nearEnd() {
    final model = widget.controller;
    if (!model.loading &&
        model.error == null &&
        model.hasMore &&
        scroll.hasClients &&
        scroll.position.extentAfter < 350) {
      model.load();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.controller;
    final items = model.items;
    final waiting =
        model.session.loggedIn &&
        (model.loading || (!model.loaded && model.error == null));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                key: ValueKey('account-${widget.name}-refresh'),
                tooltip: '刷新列表',
                onPressed: model.loading
                    ? null
                    : () => model.load(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (waiting && items.isEmpty)
          LinearProgressIndicator(
            key: ValueKey('account-${widget.name}-loading'),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => model.load(refresh: true),
            child: CustomScrollView(
              key: ValueKey('account-${widget.name}-list'),
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (items.isNotEmpty) widget.sliver(context, items),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            waiting
                                ? '正在获取账号列表'
                                : model.error ?? widget.emptyMessage,
                            key: ValueKey('account-${widget.name}-state'),
                          ),
                          if (model.error != null)
                            TextButton(
                              key: ValueKey('account-${widget.name}-retry'),
                              onPressed: () => model.load(refresh: true),
                              child: const Text('重试'),
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          if (model.error != null) ...[
                            Text(
                              model.error!,
                              key: ValueKey('account-${widget.name}-error'),
                            ),
                            TextButton(
                              key: ValueKey('account-${widget.name}-retry'),
                              onPressed: () => model.load(),
                              child: const Text('重试加载'),
                            ),
                          ] else if (!model.hasMore)
                            Text(
                              '已加载全部',
                              key: ValueKey('account-${widget.name}-end'),
                            ),
                          if (model.unsupportedCount > 0)
                            const Text('部分内容暂不支持展示'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
