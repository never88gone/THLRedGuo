import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/screen/app_layout.dart';
import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/views/download/download_picker.dart';
import 'package:THLRedLook/pages/downloads/downloads_page.dart';
import 'package:THLRedLook/core/store/local_store.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/pages/player/player_page.dart';
import 'package:THLRedLook/views/remote/remote_widgets.dart';
import 'package:THLRedLook/views/common/widgets.dart';
import 'package:THLRedLook/pages/sources/sources_page.dart';
import 'package:THLRedLook/views/browser/episode_browser.dart';
import 'package:THLRedLook/core/store/follow_state.dart';
import 'package:THLRedLook/core/series/hongguo_series.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.drama,
    required this.repository,
    required this.store,
    this.initialDetail,
    this.resumeOnOpen = false,
    this.downloadOnOpen = false,
    this.initialSeriesEntries,
    this.playerFactory,
    this.videoBuilder,
  });
  final Drama drama;
  final DramaDetail? initialDetail;
  final AppRepository repository;
  final LocalStore store;
  final bool resumeOnOpen;
  final bool downloadOnOpen;
  final List<HongguoSeriesEntry>? initialSeriesEntries;
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
          drama: _detail?.drama ?? widget.drama,
        )
      : null;

  @override
  void initState() {
    super.initState();
    _profileEpoch = widget.store.profileEpoch;
    widget.store.addListener(_onStoreChanged);
    _seriesEntries = widget.initialSeriesEntries;
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
    var drama = _detail?.drama ?? widget.drama;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      drama = await resolveHongguoSeriesIdentity(
        drama: drama,
        repository: widget.repository,
        store: widget.store,
      );
      if (!mounted ||
          generation != _generation ||
          _profileEpoch != widget.store.profileEpoch) {
        return;
      }
      final detail = await widget.repository.detail(drama);
      if (!mounted ||
          generation != _generation ||
          _profileEpoch != widget.store.profileEpoch) {
        return;
      }
      final merged = widget.repository.catalogUpdates
          .current(drama)
          .merge(detail.drama);
      final finalEpisodes = detail.episodes.isNotEmpty
          ? detail.episodes
          : (merged.episodes > 0
                ? List.generate(
                    merged.episodes,
                    (index) => Episode({
                      'id': '${merged.cleanSourceId}_${index + 1}',
                      'title': '第 ${index + 1} 集',
                      'currentEpisode': index + 1,
                    }, index + 1),
                  )
                : <Episode>[]);
      setState(() {
        _detail = DramaDetail(merged, finalEpisodes, warning: detail.warning);
        _seriesEntries = hongguoSeriesEntries(merged, [
          ...?_seriesEntries?.map((entry) => entry.drama),
          ...widget.store.seriesDramasFor(merged),
        ], lockedEntries: _seriesEntries);
        _loading = false;
        _episodePage =
            resumeEpisodeIndex(
              finalEpisodes,
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
        widget.repository.catalogUpdates.current(drama),
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
        existingEntries: _seriesEntries,
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
          initialSeriesEntries: _seriesEntries,
          onSeasonChanged: _playerSeasonChanged,
        ),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _playerSeasonChanged(DramaDetail detail) {
    if (!mounted || _profileEpoch != widget.store.profileEpoch) return;
    _generation++;
    setState(() {
      _detail = detail;
      _seriesEntries = hongguoSeriesEntries(detail.drama, [
        ...?_seriesEntries?.map((entry) => entry.drama),
        ...widget.store.seriesDramasFor(detail.drama),
      ], lockedEntries: _seriesEntries);
      _loading = false;
      _error = null;
      _expandedDescription = false;
      _episodePage =
          resumeEpisodeIndex(
            detail.episodes,
            widget.store.watched(detail.drama.id),
          ) ~/
          episodePageSize;
    });
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
    final safeDrama = drama.sourceId.isEmpty || drama.sourceId.contains(':')
        ? Drama(
            id: drama.id,
            source: drama.source,
            sourceId: drama.cleanSourceId,
            title: drama.title,
            description: drama.description,
            cover: drama.cover,
            episodes: drama.episodes,
            category: drama.category,
            heat: drama.heat,
            views: drama.views,
            onlineDate: drama.onlineDate,
            tags: drama.tags,
            releaseStatus: drama.releaseStatus,
          )
        : drama;
    final currentEntries =
        (_seriesEntries != null && _seriesEntries!.isNotEmpty)
        ? _seriesEntries
        : hongguoSeriesEntries(anchor, widget.store.seriesDramasFor(anchor));
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          drama: safeDrama,
          repository: widget.repository,
          store: widget.store,
          initialSeriesEntries: currentEntries,
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
                // 1. 顶部大图海报毛玻璃托底背景（深度暗色渐变遮罩，保证强光背景下文字极致清晰）
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 560,
                  child: DramaBackdrop(
                    drama: drama,
                    repository: widget.repository,
                    sigma: 36.0,
                    fadeBottom: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.blackWithAlpha(0.55),
                        AppColors.blackWithAlpha(0.80),
                        Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.96),
                        Theme.of(context).colorScheme.surface,
                      ],
                      stops: const [0.0, 0.45, 0.82, 1.0],
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
                                child: Column(
                                  children: [
                                    _seriesSelector(drama),
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 200),
                                        child: _loading ||
                                                _error != null ||
                                                episodes.isEmpty
                                            ? _episodeStatus()
                                            : EpisodeBrowser(
                                                key: const ValueKey('episode-browser'),
                                                episodes: episodes,
                                                currentNumber: watched?.episode,
                                                onSelected: (index) =>
                                                    _play(index),
                                              ),
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
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  8,
                                ),
                                child: _overview(drama),
                              ),
                            ),
                            SliverToBoxAdapter(child: _seriesSelector(drama)),
                            if (_error != null || (!_loading && episodes.isEmpty))
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _episodeStatus(),
                              )
                            else if (_loading && episodes.isEmpty)
                              SliverToBoxAdapter(
                                child: _episodeSummaryPlaceholder(drama),
                              )
                            else ...[
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
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    4,
                                    20,
                                    24,
                                  ),
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
                                        key: ValueKey(
                                          'episode-${episode.number}',
                                        ),
                                        number: episode.number,
                                        vip: episode.vip,
                                        current:
                                            episode.number == watched?.episode,
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
                    : Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow:
                                allowed && !_loading && episodes.isNotEmpty
                                ? AppShadows.primaryGlow
                                : null,
                          ),
                          child: FilledButton.icon(
                            key: const ValueKey('start-play'),
                            autofocus: television,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.hongguoRed,
                              foregroundColor: AppColors.white,
                              disabledBackgroundColor: AppColors.hongguoRed
                                  .withValues(alpha: 0.65),
                              disabledForegroundColor: AppColors.whiteWithAlpha(0.85),
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
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 28,
                            ),
                            label: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                _loading
                                    ? (watched != null
                                        ? '继续播放 · 第 ${watched.episode} 集'
                                        : '立即播放')
                                    : (watched != null && episodes.isNotEmpty
                                          ? '继续播放 · 第 ${episodes[resumeIndex].number} 集'
                                          : '立即播放'),
                                key: ValueKey(
                                  'play-label-${_loading ? "loading" : "ready"}-${watched?.episode}',
                                ),
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

  Widget _episodeSummaryPlaceholder(Drama drama) {
    final colors = Theme.of(context).colorScheme;
    final total = drama.episodes > 0 ? ' · 共 ${drama.episodes} 集' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
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
              Icon(
                Icons.grid_view_rounded,
                color: colors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '选集$total',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _episodeStatus() {
    if (_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                '正在加载选集与播放信息...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '正在获取剧集分集列表，请稍候片刻',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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
          key: const ValueKey('detail-episodes-toggle'),
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

  void _showCoverBigImage(BuildContext context, Drama drama) {
    if (drama.cover.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: AppColors.blackWithAlpha(0.92),
      builder: (dialogContext) {
        return GestureDetector(
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Scaffold(
            backgroundColor: AppColors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 3.5,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DramaCover(
                          drama: drama,
                          repository: widget.repository,
                          radius: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _overview(Drama drama) {
    final colors = Theme.of(context).colorScheme;
    final metaInfo = [
      if (drama.releaseStatus.isNotEmpty && drama.releaseStatus != 'unknown')
        drama.releaseLabel,
      if (drama.onlineDate.isNotEmpty) '${drama.onlineDate} 上线',
      if (drama.heat.isNotEmpty) '热度 ${drama.heat}',
      if (drama.views.isNotEmpty) '播放 ${drama.views}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              key: const ValueKey('drama-cover-preview'),
              onTap: () => _showCoverBigImage(context, drama),
              child: Tooltip(
                message: '点击查看海报大图',
                child: Hero(
                  tag: 'drama-cover-${widget.drama.id}',
                  child: SizedBox(
                    width: 126,
                    height: 189,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DramaCover(
                            drama: drama,
                            repository: widget.repository,
                            radius: 14,
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.blackWithAlpha(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.zoom_in_rounded,
                              size: 14,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
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
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.7,
                            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.7,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            drama.displayCategory,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (drama.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final tag in drama.tags.take(4))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (metaInfo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.blackWithAlpha(0.40),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.whiteWithAlpha(0.12),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          metaInfo.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (drama.vip &&
                      drama.source != 'hongguo' &&
                      !drama.id.startsWith('hongguo:'))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'VIP 内容',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 8),
                  _followingControls(drama),
                ],
              ),
            ),
          ],
        ),
        if (drama.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.2),
                width: 0.6,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  drama.description,
                  maxLines: _expandedDescription ? null : 3,
                  overflow: _expandedDescription
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.95),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                if (drama.description.length > 40)
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => setState(
                        () => _expandedDescription = !_expandedDescription,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _expandedDescription ? '收起简介' : '展开简介',
                          style: const TextStyle(
                            color: AppColors.hongguoRed,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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

    final notices = widget.store.following(drama.id)?.seriesSeasons ?? const {};

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: entries.isEmpty
          ? const SizedBox.shrink()
          : Container(
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
                          onTap: isCurrent || !entry.playable
                              ? null
                              : () => _openSeriesDrama(entry.drama),
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
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                  constraints: const BoxConstraints(
                                    maxWidth: 160,
                                  ),
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
    ),
  );
}

  Color _followStatusColor(FollowStatus status) {
    switch (status) {
      case FollowStatus.planned:
        return AppColors.hongguoAmber;
      case FollowStatus.watching:
        return AppColors.hongguoRed;
      case FollowStatus.watched:
        return AppColors.success;
    }
  }

  IconData _followStatusIcon(FollowStatus status, {bool filled = true}) {
    switch (status) {
      case FollowStatus.planned:
        return filled ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded;
      case FollowStatus.watching:
        return filled
            ? Icons.play_circle_fill_rounded
            : Icons.play_circle_outline_rounded;
      case FollowStatus.watched:
        return filled
            ? Icons.check_circle_rounded
            : Icons.check_circle_outline_rounded;
    }
  }

  String _followStatusDescription(FollowStatus status) {
    switch (status) {
      case FollowStatus.planned:
        return '加入想看清单，不错过更新提醒';
      case FollowStatus.watching:
        return '正在追更中，首页常驻快速观看';
      case FollowStatus.watched:
        return '已看完本剧全部集数';
    }
  }

  Widget _buildStatusOptionTile({
    required BuildContext sheetContext,
    required Drama drama,
    required FollowStatus status,
    required bool isSelected,
  }) {
    final colors = Theme.of(sheetContext).colorScheme;
    final statusColor = _followStatusColor(status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          Navigator.of(sheetContext).pop();
          if (_profileEpoch != widget.store.profileEpoch) return;
          await saveUserChange(
            context,
            () => widget.store.setFollowStatus(drama, status),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? statusColor.withValues(alpha: 0.12)
                : colors.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? statusColor.withValues(alpha: 0.55)
                  : colors.outlineVariant.withValues(alpha: 0.25),
              width: isSelected ? 1.4 : 0.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? statusColor.withValues(alpha: 0.2)
                      : colors.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _followStatusIcon(status, filled: isSelected),
                  color: isSelected ? statusColor : colors.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected ? statusColor : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _followStatusDescription(status),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  color: statusColor,
                  size: 22,
                )
              else
                Icon(
                  Icons.circle_outlined,
                  color: colors.outlineVariant.withValues(alpha: 0.4),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFollowStatusSheet(
    BuildContext context,
    Drama drama,
    FollowState? state,
  ) async {
    final colors = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.2),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color:
                                colors.onSurfaceVariant.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '追剧与观看状态',
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  drama.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            color: colors.onSurfaceVariant,
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      for (final status in FollowStatus.values) ...[
                        _buildStatusOptionTile(
                          sheetContext: sheetContext,
                          drama: drama,
                          status: status,
                          isSelected: state?.status == status,
                        ),
                        if (status != FollowStatus.values.last)
                          const SizedBox(height: 8),
                      ],
                      if (state != null) ...[
                        const SizedBox(height: 14),
                        Divider(
                          height: 1,
                          thickness: 0.8,
                          color: colors.outlineVariant.withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            if (_profileEpoch != widget.store.profileEpoch) {
                              return;
                            }
                            await saveUserChange(
                              context,
                              () => widget.store.toggleFavorite(drama),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.bookmark_remove_outlined,
                                  size: 18,
                                  color: AppColors.hongguoRed,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '从追剧清单中移出',
                                  style: TextStyle(
                                    color: AppColors.hongguoRed,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _followingControls(Drama drama) {
    final state = widget.store.following(drama.id);
    final colors = Theme.of(context).colorScheme;
    final isFollowed = state != null;
    final statusColor = isFollowed
        ? _followStatusColor(state.status)
        : colors.onSurface;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Material(
          color: Colors.transparent,
          child: Tooltip(
            message: '追剧与观看状态',
            child: InkWell(
              key: const ValueKey('follow-status'),
              onTap: () => _showFollowStatusSheet(context, drama, state),
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isFollowed
                      ? statusColor.withValues(alpha: 0.14)
                      : colors.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isFollowed
                        ? statusColor.withValues(alpha: 0.45)
                        : colors.outlineVariant.withValues(alpha: 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFollowed
                          ? _followStatusIcon(state.status, filled: true)
                          : Icons.bookmark_add_outlined,
                      size: 14,
                      color: isFollowed ? statusColor : colors.onSurface,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      state?.label ?? '追剧',
                      style: TextStyle(
                        color: isFollowed ? statusColor : colors.onSurface,
                        fontSize: 11.5,
                        fontWeight:
                            isFollowed ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 14,
                      color: isFollowed ? statusColor : colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (state != null && state.hasUpdates)
          ActionChip(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            label: Text(
              '${state.updateLabel} · 标为已读',
              style: const TextStyle(fontSize: 10.5),
            ),
            onPressed: () => saveUserChange(
              context,
              () => widget.store.markUpdatesRead(drama.id),
            ),
          ),
      ],
    );
  }
}
