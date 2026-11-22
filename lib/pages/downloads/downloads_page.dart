import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/core/download/download_collections.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/downloads/offline_player_page.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/views/downloads/download_batch_bar.dart';
import 'package:THLRedLook/views/downloads/download_collection_card.dart';
import 'package:THLRedLook/views/downloads/download_filter_dialog.dart';
import 'package:THLRedLook/views/downloads/download_job_card.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.embedded = false,
    this.playerBuilder,
  });
  final AppRepository repository;
  final LocalStore store;
  final bool embedded;
  @visibleForTesting
  final Widget Function(DramaDetail, int, double)? playerBuilder;
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  Timer? _timer;
  final _search = TextEditingController();
  final _selected = <String>{};
  final _expanded = <String>{};
  late final DownloadCollectionUpdater _updater;
  late final int _epoch;
  List<DownloadJob> _jobs = [];
  bool _loading = true,
      _refreshing = false,
      _opening = false,
      _selecting = false,
      _busy = false,
      _stopBatch = false;
  String? _error, _retryCommand;
  String _filter = 'all', _release = '', _operation = '';
  bool get _allowed =>
      widget.store.profileEpoch == _epoch && widget.store.canDownload;
  List<DownloadCollection> get _collections {
    final currentSource = widget.store.source;
    final filtered = currentSource.isEmpty
        ? _jobs
        : _jobs.where((job) {
            final jobSource = job.drama.source.isNotEmpty
                ? job.drama.source
                : (job.drama.id.contains(':')
                      ? job.drama.id.split(':').first
                      : '');
            return jobSource == currentSource;
          }).toList();
    return downloadCollections(
      filtered,
      query: _search.text,
      filter: _filter,
      release: _release,
    );
  }

  @override
  void initState() {
    super.initState();
    _epoch = widget.store.profileEpoch;
    _updater = DownloadCollectionUpdater(widget.repository, widget.store)
      ..addListener(_changed);
    widget.store.addListener(_changed);
    if (widget.repository.supportsDownloads) {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    } else {
      _loading = false;
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stopBatch = true;
    _timer?.cancel();
    _search.dispose();
    widget.store.removeListener(_changed);
    _updater.removeListener(_changed);
    _updater.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing || !_allowed) return;
    _refreshing = true;
    try {
      final jobs = await widget.repository.downloads();
      if (mounted && _allowed) {
        setState(() {
          _jobs = jobs;
          _selected.retainAll(jobs.map((job) => job.id));
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && _allowed) setState(() => _error = error.toString());
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _batch(String command, Iterable<DownloadJob> source) async {
    if (_busy || !_allowed) return;
    final jobs = source.where((job) => switch (command) {
      'pause' => job.active,
      'resume' => job.resumable,
      'archive' => job.completed && !job.archived,
      'restore' => job.completed && job.archived,
      'remove' => true,
      _ => false,
    }).toList();
    if (jobs.isEmpty) {
      _message('没有适合此操作的任务');
      return;
    }
    if (command == 'remove') {
      final completed = jobs.where((job) => job.completed).length;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(completed > 0 ? '删除所选视频？' : '取消所选下载？'),
          content: Text(
            '共 ${jobs.length} 项${completed > 0 ? '，包含 $completed 个已下载视频' : ''}，文件也会删除。\n需要保留视频时，请选择“清理任务，保留视频”。',
          ),
          actions: [
            TextButton(
              autofocus: AppLayout.isTelevision(context),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted || !_allowed) return;
    }
    setState(() {
      _busy = true;
      _stopBatch = false;
      _retryCommand = null;
    });
    final failures = <String, String>{};
    var completed = 0;
    try {
      for (var offset = 0; offset < jobs.length; offset += 500) {
        if (!mounted || !_allowed || _stopBatch) break;
        final end = math.min(offset + 500, jobs.length);
        setState(() => _operation = '正在处理 $end/${jobs.length} 项');
        final ids = jobs.sublist(offset, end).map((job) => job.id).toList();
        try {
          final result = await widget.repository.controlDownloadBatch(command, ids);
          if (!mounted || !_allowed) return;
          completed += result.completed.length;
          _selected.removeAll(result.completed);
          failures.addAll(result.failures);
        } catch (error) {
          failures.addAll({for (final id in ids) id: error.toString()});
        }
      }
      if (!mounted || !_allowed) return;
      if (failures.isNotEmpty) {
        _selected.addAll(failures.keys);
        _selecting = true;
        _retryCommand = command;
        _message('已处理 $completed 项，${failures.length} 项失败：${failures.values.first}');
      } else {
        _message(_stopBatch
            ? '已停止，已处理 $completed 项'
            : command == 'archive'
            ? '已清理 $completed 项任务，视频仍可本地播放'
            : '已处理 $completed 项');
      }
      await _refresh();
    } finally {
      if (mounted) setState(() { _busy = false; _operation = ''; });
    }
  }

  Future<void> _update(Drama drama) async {
    await _updater.update(drama);
    if (mounted && _allowed) {
      _message(_updater.error ?? _updater.status);
      await _refresh();
    }
  }

  Future<void> _play(DownloadJob job) async {
    if (_opening || !_allowed) return;
    _opening = true;
    final completed = _jobs
        .where((entry) => entry.completed && entry.drama.id == job.drama.id)
        .toList()
      ..sort((a, b) => a.episode.number.compareTo(b.episode.number));
    final index = completed.indexWhere((entry) => entry.id == job.id);
    if (index < 0) {
      _opening = false;
      return;
    }
    final detail = DramaDetail(
      job.drama,
      completed.map((entry) => entry.episode).toList(),
    );
    final watch = widget.store.watched(job.drama.id);
    final position = watch?.episode == job.episode.number && !watch!.finished
        ? watch.position
        : 0.0;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.playerBuilder?.call(detail, index, position) ??
              OfflinePlayerPage(
                drama: job.drama,
                completedJobs: completed,
                initialIndex: index,
                repository: widget.repository,
                store: widget.store,
              ),
        ),
      );
    } finally {
      _opening = false;
      if (mounted) await _refresh();
    }
  }

  void _select(Iterable<DownloadJob> jobs) {
    final ids = jobs.map((job) => job.id).toSet();
    setState(() {
      _selecting = true;
      if (ids.every(_selected.contains)) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  Future<void> _filters() async {
    final result = await showDownloadFilterDialog(
      context: context,
      currentFilter: _filter,
      currentRelease: _release,
    );
    if (result != null && mounted) {
      setState(() {
        _filter = result['filter']!;
        _release = result['release']!;
      });
    }
  }

  List<Widget> _titleActions(List<DownloadCollection> collections) => [
    if (_selecting) ...[
      IconButton(
        tooltip: '全选当前',
        onPressed: _busy ? null : () => _select(collections.expand((c) => c.jobs)),
        icon: const Icon(Icons.select_all_rounded),
      ),
      IconButton(
        tooltip: '退出多选',
        onPressed: _busy ? null : () => setState(() {
          _selecting = false;
          _selected.clear();
          _retryCommand = null;
        }),
        icon: const Icon(Icons.close_rounded),
      ),
    ] else ...[
      IconButton(
        tooltip: '筛选下载合集',
        onPressed: _filters,
        icon: Badge(
          isLabelVisible: _filter != 'all' || _release.isNotEmpty,
          child: const Icon(Icons.filter_list_rounded),
        ),
      ),
      IconButton(
        tooltip: '多选下载任务',
        onPressed: () => setState(() => _selecting = true),
        icon: const Icon(Icons.checklist_rounded),
      ),
    ],
    PopupMenuButton<String>(
      key: const ValueKey('download-queue-actions'),
      tooltip: '队列操作',
      enabled: !_busy,
      onSelected: (value) async {
        if (value == 'refresh') {
          _refresh();
        } else if (value == 'pauseAll') {
          await widget.repository.controlDownloads('pauseAll');
          await _refresh();
        } else if (value == 'resumeAll') {
          await widget.repository.controlDownloads('resumeAll');
          await _refresh();
        } else {
          _batch(value, _jobs);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'pauseAll', child: Text('全部暂停')),
        PopupMenuItem(value: 'resumeAll', child: Text('全部继续')),
        PopupMenuItem(value: 'archive', child: Text('清理已完成任务，保留视频')),
        PopupMenuItem(value: 'refresh', child: Text('刷新记录')),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.supportsDownloads) {
      return const StatusPanel(
        title: '当前版本尚未提供下载',
        message: '下载传输、断点续传与离线播放服务尚未接入，可继续使用在线播放。',
      );
    }
    if (!_allowed) {
      return const StatusPanel(title: '当前用户无权访问下载', message: '请返回后重新操作。');
    }
    final tv = AppLayout.isTelevision(context);
    final collections = _collections;
    final rows = <Object>[
      for (final collection in collections) ...[
        collection,
        if (_expanded.contains(collection.drama.id) || collections.length == 1 || tv)
          ...collection.jobs,
      ],
    ];
    final title = _selecting ? '已选 ${_selected.length} 项' : '下载任务';
    final actions = _titleActions(collections);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded)
          AppBar(
            key: const ValueKey('downloads-embedded-appbar'),
            title: Text(title),
            actions: actions,
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SingleChildScrollView(
            key: const ValueKey('download-filters'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (k, label) in [
                  ('all', '全部'),
                  ('downloading', '下载中'),
                  ('completed', '已下载'),
                  ('archived', '已保留视频'),
                ]) ...[
                  ChoiceChip(
                    key: ValueKey('download-filter-$k'),
                    label: Text(label),
                    selected: _filter == k,
                    onSelected: (selected) {
                      if (selected) setState(() => _filter = k);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索剧名、站源或分类',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Text(
            '${collections.length} 部 · ${collections.fold<int>(0, (sum, c) => sum + c.jobs.length)} 集'
            '${_filter == 'archived' ? ' · 已清理任务，视频仍保留' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_updater.busy || _busy) LinearProgressIndicator(minHeight: 2),
        if (_updater.busy || _busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _busy ? _operation : _updater.status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_updater.busy)
                  TextButton(
                    onPressed: _updater.cancel,
                    child: const Text('停止'),
                  ),
              ],
            ),
          ),
        if (_error != null && _jobs.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _jobs.isEmpty
              ? StatusPanel(
                  title: '无法读取下载记录',
                  message: _error!,
                  onRetry: _refresh,
                )
              : rows.isEmpty
              ? StatusPanel(
                  title: _jobs.isEmpty ? '还没有下载任务' : '暂无符合条件的任务',
                  message: '在剧集详情选择下载，或调整筛选查看已保留的视频。',
                  icon: Icons.download_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: rows.length,
                  itemBuilder: (_, index) => switch (rows[index]) {
                    DownloadCollection collection => DownloadCollectionCard(
                      collection: collection,
                      selectedCount: collection.jobs.where((job) => _selected.contains(job.id)).length,
                      expanded: _expanded.contains(collection.drama.id),
                      selecting: _selecting,
                      busy: _busy,
                      filter: _filter,
                      updaterBusy: _updater.busy,
                      onToggleExpand: () => setState(() {
                        if (!_expanded.remove(collection.drama.id)) {
                          _expanded.add(collection.drama.id);
                        }
                      }),
                      onSelect: () => _select(collection.jobs),
                      onCommand: (cmd) => switch (cmd) {
                        'update' => _update(collection.drama),
                        'select' => _select(collection.jobs),
                        _ => _batch(cmd, collection.jobs),
                      },
                    ),
                    DownloadJob job => DownloadJobCard(
                      job: job,
                      selected: _selected.contains(job.id),
                      selecting: _selecting,
                      busy: _busy,
                      onSelect: () => _select([job]),
                      onPlay: () => _play(job),
                      onCommand: (cmd) => _batch(cmd, [job]),
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ),
        ),
        if (_selecting)
          DownloadBatchBar(
            busy: _busy,
            hasSelected: _selected.isNotEmpty,
            retryCommand: _retryCommand,
            onStopBatch: () => setState(() => _stopBatch = true),
            onBatchCommand: (cmd) => _batch(
              cmd,
              _jobs.where((job) => _selected.contains(job.id)),
            ),
          ),
      ],
    );
    if (widget.embedded) {
      return SafeArea(top: true, bottom: false, child: body);
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.goBack): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(top: false, child: body),
      ),
    );
  }
}
