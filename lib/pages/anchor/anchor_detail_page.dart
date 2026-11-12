import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

class AnchorDetailPage extends StatefulWidget {
  const AnchorDetailPage({
    super.key,
    required this.anchor,
    required this.repository,
    required this.store,
    this.initialDramas = const [],
    this.onOpenDrama,
  });

  final Anchor anchor;
  final AppRepository repository;
  final LocalStore store;
  final List<Drama> initialDramas;
  final ValueChanged<Drama>? onOpenDrama;

  @override
  State<AnchorDetailPage> createState() => _AnchorDetailPageState();
}

class _AnchorDetailPageState extends State<AnchorDetailPage> {
  late Anchor _anchor;
  late List<Drama> _dramas;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _anchor = widget.anchor;
    _dramas = widget.initialDramas;
    _loadAnchorDramas();
  }

  Future<void> _loadAnchorDramas() async {
    if (_dramas.isNotEmpty) return;
    setState(() => _loading = true);
    try {
      // 预留主播短剧作品接口，当前先保持空实现或本地占位
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _toggleFollow() {
    widget.store.toggleFollowAnchor(_anchor);
    setState(() {
      final isNowFollowed = !widget.store.isAnchorFollowed(_anchor.id);
      _anchor = _anchor.copyWith(isFollowed: isNowFollowed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFollowed = widget.store.isAnchorFollowed(_anchor.id) || _anchor.isFollowed;

    return Scaffold(
      appBar: AppBar(
        title: Text(_anchor.name),
        actions: [
          IconButton(
            tooltip: '分享主播',
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已复制 ${_anchor.name} 的主页链接')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: AppColors.hongguoRed.withValues(alpha: 0.15),
                        child: Text(
                          _anchor.name.isNotEmpty ? _anchor.name.substring(0, 1) : '主',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.hongguoRed,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _anchor.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: AppColors.hongguoOrange,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _anchor.bio.isNotEmpty ? _anchor.bio : '短剧认证创作者',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statItem(
                        context,
                        '粉丝',
                        _anchor.fansCount > 0 ? '${_anchor.fansCount}' : '1.2w',
                      ),
                      _statItem(
                        context,
                        '获赞',
                        '${(_anchor.fansCount * 2.8).toInt()}',
                      ),
                      _statItem(
                        context,
                        '作品',
                        _dramas.isNotEmpty ? '${_dramas.length}' : '${_anchor.dramasCount}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: isFollowed
                        ? OutlinedButton.icon(
                            key: const ValueKey('anchor-followed-btn'),
                            onPressed: _toggleFollow,
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('已关注'),
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                            ),
                          )
                        : FilledButton.icon(
                            key: const ValueKey('anchor-follow-btn'),
                            onPressed: _toggleFollow,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('关注主播'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.hongguoRed,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '短剧作品 (${_dramas.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: AppColors.hongguoRed)),
              )
            else if (_dramas.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.movie_creation_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '该主播暂未发布更多公开作品',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  const columns = 3;
                  final width =
                      (constraints.maxWidth - 32 - (columns - 1) * 10) / columns;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      mainAxisExtent: DramaTile.extentFor(context, width),
                    ),
                    itemCount: _dramas.length,
                    itemBuilder: (context, index) {
                      final drama = _dramas[index];
                      return DramaTile(
                        key: ValueKey('anchor-drama-${drama.id}'),
                        drama: drama,
                        repository: widget.repository,
                        onTap: () => widget.onOpenDrama?.call(drama),
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _statItem(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
