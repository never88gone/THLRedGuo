import 'package:flutter/material.dart';
import '../../core/account/hongguo_account_service.dart';
import '../../core/account/hongguo_account_session.dart';
import '../../core/bridge/core_bridge.dart';
import '../../core/store/local_store.dart';
import '../../models/catalog/models.dart';
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
  int generation = 0;
  late int revision = service.session.revision;
  @override
  void initState() {
    super.initState();
    service.session.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (revision == service.session.revision) return;
    revision = service.session.revision;
    generation++;
    if (mounted) {
      setState(() {
        profile = null;
        error = null;
        writing = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await service.creatorProfile(widget.anchor.id);
      if (mounted && ticket == generation) setState(() => profile = value);
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

  Future<void> _follow() async {
    final current = profile;
    if (current == null || writing || current.officialFollowing == null) return;
    final ticket = ++generation;
    setState(() {
      writing = true;
      error = null;
    });
    try {
      final value = await service.setProfileFollowing(
        current,
        !current.officialFollowing!,
      );
      if (mounted && ticket == generation) {
        setState(() => profile = value);
        widget.onFollowingChanged?.call();
      }
    } catch (issue) {
      if (mounted && ticket == generation) {
        setState(
          () => error = issue is HongguoAccountFailure
              ? issue.message
              : '关注操作失败，请重试',
        );
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
    final value = profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(value?.name ?? '主播详情'),
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
        padding: const EdgeInsets.all(20),
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
            const CircleAvatar(radius: 36, child: Icon(Icons.person, size: 40)),
            const SizedBox(height: 16),
            Text(
              value.name,
              key: const ValueKey('anchor-name'),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              value.bio.isEmpty ? '暂无简介' : value.bio,
              key: const ValueKey('anchor-bio'),
            ),
            if (value.dramasCount != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '作品 ${value.dramasCount}',
                  key: const ValueKey('anchor-works-count'),
                ),
              ),
            FilledButton.icon(
              key: const ValueKey('anchor-official-follow'),
              onPressed:
                  loading ||
                      writing ||
                      value.officialFollowing == null ||
                      (!value.canFollow && value.officialFollowing != true)
                  ? null
                  : _follow,
              icon: Icon(
                value.officialFollowing == true ? Icons.check : Icons.add,
              ),
              label: Text(
                writing
                    ? '正在确认'
                    : value.officialFollowing == true
                    ? '已关注'
                    : value.officialFollowing == null
                    ? '关注状态暂不可用'
                    : '关注',
              ),
            ),
            const SizedBox(height: 24),
            if (widget.initialDramas.isNotEmpty) ...[
              Text('关联短剧', style: Theme.of(context).textTheme.titleMedium),
              for (final drama in widget.initialDramas)
                ListTile(
                  key: ValueKey('anchor-drama-${drama.id}'),
                  title: Text(
                    widget.repository.catalogUpdates.current(drama).title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DetailScreen(
                        drama: drama,
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  ),
                ),
            ] else
              const Text('暂无可展示的关联短剧', key: ValueKey('anchor-no-works')),
          ],
        ],
      ),
    );
  }
}
