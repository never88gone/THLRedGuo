import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app_colors.dart';
import 'app_layout.dart';
import 'core_bridge.dart';
import 'download_picker.dart';
import 'downloads_screen.dart';
import 'local_store.dart';
import 'models.dart';
import 'player_screen.dart';
import 'remote_widgets.dart';
import 'widgets.dart';
import 'sources_screen.dart';
import 'episode_browser.dart';
import 'follow_state.dart';
import 'hongguo_series.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.drama,
    required this.repository,
    required this.store,
    this.initialDetail,
    this.resumeOnOpen = false,
    this.downloadOnOpen = false,
    this.playerFactory,
    this.videoBuilder,
  });
  final Drama drama;
  final DramaDetail? initialDetail;
  final AppRepository repository;
  final LocalStore store;
  final bool resumeOnOpen;
  final bool downloadOnOpen;
  @visibleForTesting
  final Player Function()? playerFactory;
  @visibleForTesting
  final Widget Function(Widget controls)? videoBuilder;
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  DramaDetail? _detail;
  String? _error;
  bool _loading = true;
  int _generation = 0;
  int _episodePage = 0;
  bool _expandedDescription = false;
  bool _episodesExpanded = false;
  final _episodeAnchor = GlobalKey();
  final _detailScroll = ScrollController();
  bool _initialActionHandled = false;
  late final int _profileEpoch;
  List<HongguoSeriesEntry>? _seriesEntries;
  Widget? get _sourceDiagnostics => widget.repository.supportsSourceManagement
      ? SourceDiagnosticsButton(
          repository: widget.repository,
          store: widget.store,
          drama: widget.drama,
        )
      : null;

  @override
  void initState() {
    super.initState();
    _profileEpoch = widget.store.profileEpoch;
    widget.store.addListener(_onStoreChanged);
    if (widget.initialDetail != null) {
      _detail = widget.initialDetail;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant DetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
  }

  @override
  void dispose() {
    _detailScroll.dispose();
    widget.store.removeListener(_onStoreChanged);
    _generation++;
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.detail(widget.drama);
      if (!mounted ||
          generation != _generation ||
          _profileEpoch != widget.store.profileEpoch) {
        return;
      }
      final merged = widget.repository.catalogUpdates
          .current(widget.drama)
          .merge(detail.drama);
      setState(() {
        _detail = DramaDetail(merged, detail.episodes, warning: detail.warning);
        _loading = false;
        _episodePage =
            resumeEpisodeIndex(
              detail.episodes,
              widget.store.watched(merged.id),
            ) ~/
            episodePageSize;
      });
      widget.repository.catalogUpdates.publish(merged, retryCover: true);
      unawaited(_supplement(merged, generation));
      unawaited(_discoverSeasons(merged, generation));
      await saveUserChange(context, () => widget.store.refreshDrama(merged));
      if (mounted &&
          generation == _generation &&
          _profileEpoch == widget.store.profileEpoch &&
          !_initialActionHandled &&
          detail.episodes.isNotEmpty) {
        _initialActionHandled = true;
        if (widget.resumeOnOpen) {
          unawaited(
            _play(
              resumeEpisodeIndex(
                detail.episodes,
                widget.store.watched(merged.id),
              ),
              resume: true,
            ),
          );
        } else if (widget.downloadOnOpen && widget.store.canDownload) {
          unawaited(_download());
        }
      }
    } catch (error) {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
      widget.repository.catalogUpdates.publish(
        widget.repository.catalogUpdates.current(widget.drama),
        retryCover: true,
      );
    }
  }

  Future<void> _supplement(Drama drama, int generation) async {
    try {
      final fresh = await widget.repository.supplementMetadata(drama);
      if (!mounted ||
          generation != _generation ||
          fresh == null ||
          _detail == null) {
        return;
      }
      final updated = _detail!.drama.merge(fresh);
      setState(() {
        _detail = DramaDetail(
          updated,
          _detail!.episodes,
          warning: _detail!.warning,
        );
      });
      widget.repository.catalogUpdates.publish(updated);
      await saveUserChange(context, () => widget.store.refreshDrama(updated));
    } catch (_) {}
  }

  Future<void> _discoverSeasons(Drama drama, int generation) async {
    try {
      final entries = await discoverSeriesSeasons(
        anchor: drama,
        repository: widget.repository,
        store: widget.store,
      );
      if (mounted && generation == _generation && entries.isNotEmpty) {
        setState(() {
          _seriesEntries = entries;
        });
      }
    } catch (_) {}
  }

  Future<void> _download() async {
    final detail = _detail;
    if (detail == null ||
        !widget.store.canDownload ||
        _profileEpoch != widget.store.profileEpoch) {
      return;
    }
    final selection = await Navigator.of(context).push<DownloadSelection>(
      MaterialPageRoute(
        builder: (_) => DownloadPicker(
          detail: detail,
          preferences: widget.store.downloadPreferences,
        ),
      ),
    );
    if (selection == null ||
        !mounted ||
        !widget.store.canDownload ||
        _profileEpoch != widget.store.profileEpoch) {
      return;
    }
    try {
      final added = await widget.repository.enqueueDownloads(
        detail,
        selection.episodes,
        quality: selection.quality,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added == 0 ? '所选集数已在下载列表中' : '已加入 $added 集，已有任务自动跳过'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DownloadsScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _play(int index, {bool resume = false}) async {
    final detail = _detail;
    if (detail == null ||
        index < 0 ||
        index >= detail.episodes.length ||
        _profileEpoch != widget.store.profileEpoch ||
        !widget.store.allowsSource(detail.drama.source)) {
      return;
    }
    if (detail.episodes[index].vip) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('这是一集 VIP 内容'),
          content: const Text('站源可能只提供试看或限制播放。'),
          actions: [
            TextButton(
              autofocus: AppLayout.isTelevision(context),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('尝试播放'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) {
        return;
      }
    }
    final saved = widget.store.watched(detail.drama.id);
    final position =
        resume &&
            saved?.episode == detail.episodes[index].number &&
            !saved!.finished
        ? saved.position
        : 0.0;
    if (!mounted || _profileEpoch != widget.store.profileEpoch) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          detail: detail,
          initialIndex: index,
          initialPosition: position,
          repository: widget.repository,
          store: widget.store,
          playerFactory: widget.playerFactory,
          videoBuilder: widget.videoBuilder,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSeriesDrama(Drama drama) async {
    if (_profileEpoch != widget.store.profileEpoch ||
        drama.id == (_detail?.drama.id ?? widget.drama.id)) {
      return;
    }
    final anchor = _detail?.drama ?? widget.drama;
    if (widget.store.following(anchor.id)?.seriesSeasons[drama.id]?.read ==
        false) {
      await saveUserChange(
        context,
        () => widget.store.markSeriesSeasonRead(anchor.id, drama.id),
      );
      if (!mounted) return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          drama: drama,
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drama = _detail?.drama ?? widget.drama;
    final watched = widget.store.watched(drama.id);
    final episodes = _detail?.episodes ?? <Episode>[];
    final resumeIndex = resumeEpisodeIndex(episodes, watched);
    final dramaSource = drama.source.isNotEmpty
        ? drama.source
        : (widget.drama.source.isNotEmpty
            ? widget.drama.source
            : (drama.id.contains(':')
                ? drama.id.split(':').first
                : widget.store.source));
    final television = AppLayout.isTelevision(context);
    final allowed =
        widget.store.profileEpoch == _profileEpoch &&
        (widget.store.allowsSource(dramaSource) ||
            widget.store.allowsSource(widget.store.source));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.goBack): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: television ? 64 : null,
          title: Text(
            drama.title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: RefreshAction(
                loading: _loading,
                tooltip: '更新剧集信息',
                onPressed: allowed ? _load : null,
              ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Stack(
              children: [
                // 1. 顶部大图海报毛玻璃托底背景（向下自然淡化融入背景，无生硬裁切线）
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 500,
                  child: DramaBackdrop(
                    drama: drama,
                    repository: widget.repository,
                    sigma: 32.0,
                    fadeBottom: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.38),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55],
                    ),
                  ),
                ),
                // 2. 页面前景内容区域
                Positioned.fill(
                  child: SafeArea(
                    top: true,
                    bottom: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (!allowed) {
                          return const StatusPanel(
                            title: '当前用户无权访问',
                            message: '请返回剧库后重新选择。',
                          );
                        }
                        if (television || constraints.maxWidth >= 960) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: (constraints.maxWidth * .34).clamp(
                                  250.0,
                                  360.0,
                                ),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(20),
                                  child: _overview(drama),
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(
                                child: _loading || _error != null || episodes.isEmpty
                                    ? _episodeStatus()
                                    : Column(
                                        children: [
                                          _seriesSelector(drama),
                                          Expanded(
                                            child: EpisodeBrowser(
                                              episodes: episodes,
                                              currentNumber: watched?.episode,
                                              onSelected: (index) => _play(index),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          );
                        }
                        final start = _episodePage * episodePageSize;
                        final visible = episodes
                            .skip(start)
                            .take(episodePageSize)
                            .toList();
                        final showEpisodes = _episodesExpanded;
                        return CustomScrollView(
                          controller: _detailScroll,
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                                child: _overview(drama),
                              ),
                            ),
                      if (_loading || _error != null || episodes.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _episodeStatus(),
                        )
                      else ...[
                        SliverToBoxAdapter(child: _seriesSelector(drama)),
                        SliverToBoxAdapter(
                          child: _episodeSummary(
                            episodes,
                            currentNumber: watched?.episode,
                            expanded: showEpisodes,
                          ),
                        ),
                        if (showEpisodes) ...[
                          SliverToBoxAdapter(
                            child: EpisodeRangeBar(
                              key: _episodeAnchor,
                              episodes: episodes,
                              page: _episodePage,
                              title: '分组',
                              currentNumber: watched?.episode,
                              onLocate: _locateEpisode,
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _episodeColumns(
                                      constraints.maxWidth,
                                      episodes,
                                    ),
                                    mainAxisExtent: math.max(
                                      54,
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(20) +
                                          30,
                                    ),
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final episode = visible[index];
                                return RemoteEpisodeButton(
                                  key: ValueKey('episode-${episode.number}'),
                                  number: episode.number,
                                  vip: episode.vip,
                                  current: episode.number == watched?.episode,
                                  onPressed: () => _play(start + index),
                                );
                              }, childCount: visible.length),
                            ),
                          ),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  ),
  bottomNavigationBar: Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).brightness == Brightness.dark
                ? AppGradients.bottomNavGlass
                : null,
            color: Theme.of(context).brightness == Brightness.dark
                ? null
                : Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0x26FFFFFF)
                    : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 0.6,
              ),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    children: [
                      if (widget.repository.supportsDownloads &&
                          widget.store.canDownload) ...[
                        IconButton.filledTonal(
                          tooltip: '下载选集',
                          onPressed: allowed && !_loading && episodes.isNotEmpty
                              ? _download
                              : null,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(52, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.download_rounded),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: allowed && !_loading && episodes.isNotEmpty
                                ? AppShadows.primaryGlow
                                : null,
                          ),
                          child: FilledButton.icon(
                            key: const ValueKey('start-play'),
                            autofocus: television,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.hongguoRed,
                              foregroundColor: AppColors.white,
                              disabledBackgroundColor: AppColors.hongguoRed.withValues(alpha: 0.4),
                              shape: const StadiumBorder(),
                              minimumSize: const Size(0, 52),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            onPressed: !allowed || _loading || episodes.isEmpty
                                ? null
                                : () => _play(resumeIndex, resume: true),
                            icon: const Icon(Icons.play_arrow_rounded, size: 28),
                            label: Text(
                              _loading
                                  ? '正在加载...'
                                  : (watched != null && episodes.isNotEmpty
                                      ? '继续播放 · 第 ${episodes[resumeIndex].number} 集'
                                      : '立即播放'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _episodeStatus() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return StatusPanel(
      title: _error != null ? '剧集信息暂时不可用' : '暂时没有可播放的集数',
      message: _error ?? '可以更新剧集信息后重试。',
      onRetry: _load,
      secondaryAction: _sourceDiagnostics,
    );
  }

  Widget _episodeSummary(
    List<Episode> episodes, {
    required int? currentNumber,
    required bool expanded,
  }) {
    final colors = Theme.of(context).colorScheme;
    final current = currentNumber == null ? '' : ' · 当前第 $currentNumber 集';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _episodesExpanded = !expanded),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.grid_view_rounded, color: colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '选集 · ${episodes.length} 集$current',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(expanded ? '收起' : '展开'),
                const SizedBox(width: 2),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _locateEpisode(int index) {
    final episodes = _detail!.episodes;
    setState(() {
      _episodePage = index ~/ episodePageSize;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = _episodeAnchor.currentContext;
      if (!mounted || anchor == null || !_detailScroll.hasClients) return;
      final render = anchor.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final viewport = RenderAbstractViewport.maybeOf(render);
      if (viewport == null) return;
      final start = viewport.getOffsetToReveal(render, 0).offset;
      final extent = math.max(
        54,
        MediaQuery.textScalerOf(context).scale(20) + 30,
      );
      final columns = _episodeColumns(render.size.width, episodes);
      final target =
          start +
          render.size.height +
          (index % episodePageSize ~/ columns) * (extent + 10) -
          _detailScroll.position.viewportDimension * .3;
      _detailScroll.animateTo(
        target.clamp(0.0, _detailScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  int _episodeColumns(double width, List<Episode> episodes) {
    final digits = episodes.fold<int>(
      1,
      (value, episode) => math.max(value, episode.number.toString().length),
    );
    final minimum = math.max(
      82,
      MediaQuery.textScalerOf(context).scale(20) * digits * .65 + 40,
    );
    return ((width - 40) / minimum).floor().clamp(1, 12);
  }

  Widget _overview(Drama drama) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'drama-cover-${drama.id}',
              child: SizedBox(
                width: 104,
                height: 156,
                child: DramaCover(
                  drama: drama,
                  repository: widget.repository,
                  radius: 14,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.hongguoRed.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.hongguoRed.withValues(alpha: 0.35),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          SourceSite.byId(drama.source).name,
                          style: const TextStyle(
                            color: AppColors.hongguoRed,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (drama.episodes > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '共 ${drama.episodes} 集',
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (drama.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            drama.category,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (drama.releaseStatus.isNotEmpty && drama.releaseStatus != 'unknown')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        drama.releaseLabel,
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  if (drama.vipStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        drama.vip
                            ? 'VIP 内容'
                            : '免费内容',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _followingControls(drama),
        if (drama.onlineDate.isNotEmpty ||
            drama.heat.isNotEmpty ||
            drama.views.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              [
                if (drama.onlineDate.isNotEmpty) '${drama.onlineDate} 上线',
                if (drama.heat.isNotEmpty) '热度 ${drama.heat}',
                if (drama.views.isNotEmpty) '播放 ${drama.views}',
              ].join(' · '),
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ),
        if (drama.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in drama.tags.take(12))
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Text(
                        tag,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (drama.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            drama.description,
            maxLines: _expandedDescription ? null : 3,
            overflow: _expandedDescription
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  setState(() => _expandedDescription = !_expandedDescription),
              child: Text(_expandedDescription ? '收起简介' : '展开简介'),
            ),
          ),
        ],
        if (_detail?.warning.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _detail!.warning,
              style: TextStyle(color: colors.error),
            ),
          ),
      ],
    );
  }

  Widget _seriesSelector(Drama drama) {
    final localEntries = hongguoSeriesEntries(
      drama,
      widget.store.seriesDramasFor(drama),
    );
    final entries = (_seriesEntries != null && _seriesEntries!.isNotEmpty)
        ? _seriesEntries!
        : localEntries;
    if (entries.isEmpty) return const SizedBox.shrink();

    final notices = widget.store.following(drama.id)?.seriesSeasons ?? const {};

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.whiteWithAlpha(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.layers_rounded,
                size: 18,
                color: AppColors.hongguoRed,
              ),
              const SizedBox(width: 6),
              const Text(
                '系列多季',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accentTrack35,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '共 ${entries.length} 季',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.hongguoRed,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                '快速切季',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in entries) ...[
                  Builder(
                    builder: (context) {
                      final isCurrent = entry.drama.id == drama.id;
                      final watched = widget.store.watched(entry.drama.id);
                      final isNew = notices[entry.drama.id]?.read == false;

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          key: ValueKey('series-${entry.drama.id}'),
                          onTap: isCurrent ? null : () => _openSeriesDrama(entry.drama),
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: isCurrent ? AppGradients.primary : null,
                              color: isCurrent
                                  ? null
                                  : AppColors.darkSurfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: isCurrent ? AppShadows.pillGlow : null,
                              border: Border.all(
                                color: isCurrent
                                    ? AppColors.hongguoRed
                                    : (isNew
                                        ? AppColors.hongguoRedWithAlpha(0.6)
                                        : AppColors.whiteWithAlpha(0.12)),
                                width: isCurrent ? 1.2 : 0.8,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      entry.label,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.whiteWithAlpha(0.25),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          '当前',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ] else if (isNew) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.hongguoRed,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'NEW',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 160),
                                  child: Text(
                                    watched != null
                                        ? '看至第${watched.episode}集'
                                        : (isCurrent
                                            ? '正在浏览'
                                            : entry.drama.title),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isCurrent
                                          ? AppColors.whiteWithAlpha(0.85)
                                          : AppColors.textTertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _followingControls(Drama drama) {
    final state = widget.store.following(drama.id);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<String>(
          key: const ValueKey('follow-status'),
          tooltip: '追剧与观看状态',
          onSelected: (value) async {
            if (_profileEpoch != widget.store.profileEpoch) return;
            if (value == 'remove') {
              await saveUserChange(
                context,
                () => widget.store.toggleFavorite(drama),
              );
            } else {
              final status = FollowStatus.values.firstWhere(
                (status) => status.name == value,
              );
              await saveUserChange(
                context,
                () => widget.store.setFollowStatus(drama, status),
              );
            }
          },
          itemBuilder: (_) => [
            for (final status in FollowStatus.values)
              CheckedPopupMenuItem(
                value: status.name,
                checked: state?.status == status,
                child: Text(status.label),
              ),
            if (state != null)
              const PopupMenuItem(value: 'remove', child: Text('取消追剧')),
          ],
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: state == null
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state?.status == FollowStatus.watched
                      ? Icons.check_circle_outline
                      : state == null
                      ? Icons.bookmark_add_outlined
                      : Icons.bookmark_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(state?.label ?? '加入追剧'),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
        if (state != null && state.hasUpdates)
          ActionChip(
            label: Text('${state.updateLabel} · 标为已读'),
            onPressed: () => saveUserChange(
              context,
              () => widget.store.markUpdatesRead(drama.id),
            ),
          ),
      ],
    );
  }
}
