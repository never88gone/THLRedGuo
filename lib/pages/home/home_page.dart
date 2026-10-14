import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_colors.dart';
import '../../js_source_presets.dart';
import '../settings/js_sources_page.dart';

import '../../app_layout.dart';
import '../../app_bottom_navigation.dart';
import '../../core_bridge.dart';
import '../../catalog_filters.dart';
import '../../catalog_browser.dart';
import '../../catalog_sort.dart';
import '../../catalog_sort_sheet.dart';
import '../../recommendations_screen.dart';
import '../../rankings_screen.dart';
import '../../detail_screen.dart';
import '../../downloads_screen.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../../remote_widgets.dart';
import '../../widgets.dart';
import '../../vip_icon.dart';
import '../settings/settings_page.dart';
import '../about/about_page.dart';
import '../../sources_screen.dart';
import '../../source_switcher_sheet.dart';
import '../../batch_download_screen.dart';
import '../../batch_downloads.dart';
import '../../drama_actions.dart';
import '../../library_updater.dart';
import '../../saved_library.dart';
import '../../views/home/home_selection_bar_view.dart';
import '../../views/home/home_search_bar_view.dart';
import '../../views/home/home_catalog_view.dart';
import '../../views/home/home_app_bar_view.dart';
import '../../js_source_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, required this.store});
  final AppRepository repository;
  final LocalStore store;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _recommendationCategory = 'app:recommendations';
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  late SourceSite _source;
  bool _allSources = false;
  List<Drama> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _generation = 0;
  int _tab = 0;
  String _submittedQuery = '';
  final _categorySelections = <String, String>{};
  late final CatalogBrowser _browser;
  bool _searchVisible = false;
  bool _categoriesLoading = false;
  String? _categoriesError;
  int _categoryGeneration = 0;
  late final LibraryUpdater _updater;
  final _changedSources = <String>{};
  final _selectedDramas = <String, Drama>{};
  Timer? _cacheRefreshTimer;
  bool _refreshingUpdatedCache = false;
  bool _selectionMode = false;
  bool _showRecommendations = false;
  String _sourceSignature = '';
  bool _catalogLoadScheduled = false;
  bool _switchingSource = false;

  List<SourceGroup> get _sourceGroups {
    return SourceGroup.fromSources(widget.store.sources);
  }

  SourceGroup get _group =>
      _sourceGroups
          .where((group) => group.id == _source.groupId)
          .firstOrNull ??
      SourceGroup(_source.groupId, _source.groupName, [_source]);
  bool get _onlineSearch => _group.sources.any((source) => source.onlineSearch);
  bool get _searchSuggestions =>
      _group.sources.any((source) => source.searchSuggestions);
  String get _searchHint {
    final online = _group.sources
        .where((source) => source.onlineSearch)
        .toList();
    if (online.isEmpty) {
      return '筛选本机已更新剧库';
    }
    final names = online.map((source) => source.name).join('、');
    return online.length == _group.sources.length
        ? '搜索$names'
        : '搜索$names及本机剧库';
  }

  String get _category => _categorySelections[_group.id] ?? '';
  List<CatalogCategory> get _categories => _browser.categories(_group);
  String get _displayCategory =>
      _showRecommendations ? _recommendationCategory : _category;
  List<CatalogCategory> get _displayCategories => [
    CatalogCategory.all,
    if (_group.id == 'hongguo')
      const CatalogCategory(_recommendationCategory, '推荐'),
    ..._categories.where((entry) => entry.id.isNotEmpty),
  ];

  Future<void> _loadCategories({
    bool force = false,
    bool cacheOnly = false,
  }) async {
    final generation = ++_categoryGeneration;
    final group = _group;
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    final error = await _browser.loadCategories(
      group,
      force: force,
      cacheOnly: cacheOnly,
    );
    if (!mounted ||
        generation != _categoryGeneration ||
        group.id != _group.id) {
      return;
    }
    setState(() {
      _categoriesLoading = false;
      _categoriesError = error;
    });
    if (!_showRecommendations &&
        _category.isNotEmpty &&
        !_categories.any((entry) => entry.id == _category)) {
      _changeCategory('');
    }
  }

  Future<void> _refreshCatalog() async {
    if (widget.repository.supportsSourceManagement) {
      if (_group.sources.any((source) => _updater.busy(source.id))) return;
      _pauseCatalog();
      await _updater.update(_group.sources);
      return;
    }
    await _loadCategories(force: true);
    if (mounted) await _load(force: true);
  }

  void _updateChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasNoSourcePlugins => widget.store.sources.isEmpty;

  /// 站源或配置变更时，同步当前站源与可见站源列表。
  void _sourcesChanged() {
    if (!mounted || _switchingSource) return;
    if (_hasNoSourcePlugins) {
      setState(() {
        _items = [];
        _hasMore = false;
        _loading = false;
        _loadingMore = false;
      });
      return;
    }
    final visible = widget.store.sources;
    final signature = visible.map((site) => site.id).join(',');
    final activeJsId = JsSourceService.current?.activeSourceId ?? '';
    final targetSourceId = visible.any((s) => s.id == widget.store.source)
        ? widget.store.source
        : ((activeJsId.isNotEmpty && visible.any((s) => s.id == activeJsId))
            ? activeJsId
            : (visible.isNotEmpty ? visible.first.id : ''));

    // 当前已处于目标数据源，若可用源列表签名发生变化则刷新并重载
    if (_source.id == targetSourceId) {
      if (signature != _sourceSignature) {
        _sourceSignature = signature;
        setState(() {});
        _load(useCache: true);
        _loadCategories();
      }
      return;
    }

    final allowed = visible.map((site) => site.id).toSet();

    // 外部发生数据源切换时才平滑过渡
    if (targetSourceId.isNotEmpty && allowed.contains(targetSourceId) && _source.id != targetSourceId) {
      _sourceSignature = signature;
      _changeSource(SourceSite.byId(targetSourceId));
      return;
    }

    if (signature != _sourceSignature) {
      _sourceSignature = signature;
    }
  }

  void _catalogUpdated(String source) {
    if (!mounted) return;
    _changedSources.add(source);
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      unawaited(_reloadUpdatedCache());
    });
  }

  Future<void> _reloadUpdatedCache() async {
    if (_refreshingUpdatedCache) return;
    _refreshingUpdatedCache = true;
    final epoch = widget.store.profileEpoch;
    try {
      while (mounted &&
          _changedSources.isNotEmpty &&
          epoch == widget.store.profileEpoch) {
        final sources = Set.of(_changedSources);
        _changedSources.clear();
        final updates = <String, Drama>{};
        for (final source in sources) {
          if (!widget.store.allowsSource(source)) continue;
          try {
            final cached = await widget.repository.cached(source);
            for (final drama in cached.items) {
              if (widget.store.allowsSource(drama.source)) {
                updates[drama.id] = drama;
              }
            }
          } catch (error) {
            if (mounted && epoch == widget.store.profileEpoch) {
              setState(() => _error = '更新后读取缓存失败：$error');
            }
          }
        }
        if (!mounted || epoch != widget.store.profileEpoch) return;
        _browser.updateDramas(updates.values);
        setState(() {
          _items = [
            for (final item in _items)
              updates[item.id] == null ? item : item.merge(updates[item.id]!),
          ];
          for (final id in _selectedDramas.keys.toList()) {
            if (updates[id] != null) {
              _selectedDramas[id] = _selectedDramas[id]!.merge(updates[id]!);
            }
          }
        });
        await saveUserChange(
          context,
          () => widget.store.refreshDramas(updates.values),
        );
        if (!mounted || epoch != widget.store.profileEpoch) return;
        if (_group.sources.any((source) => sources.contains(source.id))) {
          await _loadCategories(cacheOnly: true);
          if (mounted &&
              !_loading &&
              !_loadingMore &&
              (!_onlineSearch || _search.text.trim().isEmpty)) {
            await _load(cacheOnly: true);
          }
        }
      }
    } finally {
      _refreshingUpdatedCache = false;
    }
  }

  void _changeGroup(SourceGroup group) {
    if (_group.id != group.id) {
      _changeSource(group.sources.first, allSources: false);
    }
  }

  void _changeCategory(String category) {
    if (category == _recommendationCategory && _group.id == 'hongguo') {
      if (_showRecommendations) return;
      _pauseCatalog();
      setState(() {
        _showRecommendations = true;
        _selectionMode = false;
        _selectedDramas.clear();
        _search.clear();
        _searchVisible = false;
        _submittedQuery = '';
      });
      return;
    }
    if (_category == category && !_showRecommendations) return;
    _debounce?.cancel();
    setState(() {
      _showRecommendations = false;
      _selectionMode = false;
      _selectedDramas.clear();
      _categorySelections[_group.id] = category;
      if (_onlineSearch) {
        _search.clear();
        _submittedQuery = '';
      }
      _items = [];
      _hasMore = true;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load(useCache: true);
  }

  void _swipeCategory(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 240) return;
    final categories = _displayCategories;
    final index = categories.indexWhere(
      (entry) => entry.id == _displayCategory,
    );
    final next = index + (velocity < 0 ? 1 : -1);
    if (next >= 0 && next < categories.length) {
      _changeCategory(categories[next].id);
    }
  }

  void _toggleSearch() {
    if (AppLayout.isTelevision(context)) {
      _televisionSearch();
      return;
    }
    if (_showRecommendations) _changeCategory('');
    final hadQuery = _search.text.isNotEmpty;
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) _search.clear();
    });
    if (!_searchVisible && hadQuery) _searchChanged('');
  }

  void _openRankings() {
    _pauseCatalog();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RankingsScreen(
          repository: widget.repository,
          store: widget.store,
          initialGroup: _source.id,
        ),
      ),
    );
  }

  Future<void> _openSourceSwitcher() async {
    _pauseCatalog();
    final chosen = await showSourceSwitcherSheet(
      context,
      store: widget.store,
      currentSource: _source,
      onSelect: (site) {
        _changeSource(site);
      },
    );
    if (chosen != null && mounted) {
      await _changeSource(chosen);
    }
  }

  Future<void> _manageSources() async {
    _pauseCatalog();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SourcesScreen(
          repository: widget.repository,
          store: widget.store,
          initialSource: _source.id,
        ),
      ),
    );
    if (!mounted) return;
    await _loadCategories();
    if (mounted && (!_onlineSearch || _submittedQuery.isEmpty)) {
      await _load(useCache: true);
    }
  }

  Future<void> _chooseDisplayMode() async {
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('界面模式'),
        children: [
          RadioGroup<String>(
            groupValue: widget.store.displayMode,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in const {
                  'auto': '自动识别设备',
                  'television': '电视 / 遥控器',
                  'standard': '手机 / 电脑',
                }.entries)
                  RadioListTile<String>(
                    value: mode.key,
                    autofocus: mode.key == widget.store.displayMode,
                    title: Text(mode.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selection != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setDisplayMode(selection),
      );
    }
  }

  Future<void> _televisionSearch() async {
    final query = await showDialog<String>(
      context: context,
      builder: (_) => TelevisionSearchDialog(
        initialValue: _search.text,
        title: _group.id == 'all'
            ? '搜索已开放站源'
            : _onlineSearch
            ? '搜索${_group.name}短剧'
            : '筛选当前已加载短剧',
        recentSearches: widget.store.recentSearches,
        onCancel: () => unawaited(widget.repository.cancelSuggestions()),
        suggestions: _searchSuggestions ? widget.repository.suggestions : null,
      ),
    );
    if (query != null && mounted) {
      _submitSearch(query);
    }
  }

  void _televisionBack() {
    if (_selectionMode) {
      _cancelSelection();
    } else if (_tab != 0) {
      setState(() => _tab = 0);
    } else if (_search.text.isNotEmpty) {
      _search.clear();
      _searchChanged('');
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onCatalogScroll);
    _source = SourceSite.byId(widget.store.source);
    _allSources = widget.store.catalogView.allSources;
    _sourceSignature = widget.store.sources.map((site) => site.id).join(',');
    _browser = CatalogBrowser(widget.repository);
    _updater = LibraryUpdater(
      widget.repository,
      widget.store,
      onCatalogChanged: _catalogUpdated,
    )..addListener(_updateChanged);
    _updater.startWatching();
    widget.store.addListener(_sourcesChanged);
    JsSourceService.current?.addListener(_sourcesChanged);
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    if (!_hasNoSourcePlugins) {
      _load(useCache: true);
      _loadCategories();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _updater.removeListener(_updateChanged);
    _updater.dispose();
    _cacheRefreshTimer?.cancel();
    widget.store.removeListener(_sourcesChanged);
    JsSourceService.current?.removeListener(_sourcesChanged);
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    _generation++;
    _categoryGeneration++;
    unawaited(_browser.cancel());
    unawaited(widget.repository.cancelSuggestions());
    _debounce?.cancel();
    _search.dispose();
    _scroll.removeListener(_onCatalogScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onCatalogScroll() {
    if (!mounted ||
        _showRecommendations ||
        !_hasMore ||
        _loading ||
        _loadingMore ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final threshold = (position.viewportDimension * 1.5).clamp(320.0, 900.0);
    if (position.extentAfter > threshold || _catalogLoadScheduled) return;
    _catalogLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _catalogLoadScheduled = false;
      if (!mounted ||
          _showRecommendations ||
          !_hasMore ||
          _loading ||
          _loadingMore ||
          !_scroll.hasClients) {
        return;
      }
      unawaited(_load(more: true));
    });
  }

  void _metadataChanged() {
    final drama = widget.repository.catalogUpdates.latest;
    if (!mounted || drama == null || !widget.store.allowsSource(drama.source)) {
      return;
    }
    _browser.updateDrama(drama);
    setState(() {
      _items = [
        for (final item in _items)
          item.id == drama.id ? item.merge(drama) : item,
      ];
    });
    unawaited(saveUserChange(context, () => widget.store.refreshDrama(drama)));
  }

  Future<void> _load({
    bool more = false,
    bool useCache = false,
    bool force = false,
    bool cacheOnly = false,
  }) async {
    if (_showRecommendations) return;
    if (more && (_loading || _loadingMore || !_hasMore)) return;
    final generation = ++_generation;
    final group = _group;
    final query = _onlineSearch ? _search.text.trim() : '';
    setState(() {
      _error = null;
      if (query.isNotEmpty) _categorySelections[group.id] = '';
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
        if (query != _submittedQuery) _items = [];
      }
    });
    void accept(CatalogPage result, {bool cached = false}) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = result.items;
        _hasMore = result.hasMore;
        _submittedQuery = query;
        _loading = cached && !result.fresh;
        _loadingMore = false;
        _error =
            (force || result.items.isEmpty) && result.warning.isNotEmpty
                ? result.warning
                : null;
      });
      unawaited(
        saveUserChange(context, () => widget.store.refreshDramas(result.items)),
      );
    }

    try {
      final result = await _browser.load(
        group,
        category: _category,
        query: query,
        more: more,
        useCache: useCache,
        force: force,
        cacheOnly: cacheOnly,
        onCached: (result) => accept(result, cached: true),
      );
      accept(result);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = (force || _items.isEmpty) ? error.toString() : null;
      });
    }
  }

  Future<void> _changeSource(SourceSite source, {bool allSources = false}) async {
    if (_source.id == source.id && _allSources == allSources) {
      return;
    }
    if (_switchingSource) return;
    _switchingSource = true;
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _showRecommendations = false;
      _selectionMode = false;
      _selectedDramas.clear();
      _source = source;
      _allSources = allSources;
      _items = [];
      _hasMore = true;
      _submittedQuery = '';
      _error = null;
    });

    try {
      if (widget.store.source != source.id ||
          widget.store.catalogView.allSources != allSources) {
        await saveUserChange(
          context,
          () => widget.store.setCatalogSource(source.id, allSources: allSources),
        );
      }
      try {
        await widget.repository.jsSourceSetActive(source.id);
        if (JsSourceService.current != null &&
            JsSourceService.current!.activeSourceId != source.id) {
          await JsSourceService.current!.switchSource(source.id);
        }
      } catch (_) {}
    } finally {
      if (mounted) {
        _switchingSource = false;
      }
    }

    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    _load(useCache: true);
    _loadCategories();
  }

  void _searchChanged(String query) {
    _debounce?.cancel();
    _selectionMode = false;
    _selectedDramas.clear();
    if (_onlineSearch && (_loading || _loadingMore)) {
      _generation++;
      unawaited(_browser.cancel());
      _loading = _loadingMore = false;
    }
    setState(() {});
    if (_onlineSearch && query.trim().isEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), () => _load());
    }
  }

  void _submitSearch(String query) {
    if (_showRecommendations) {
      _showRecommendations = false;
      _categorySelections[_group.id] = '';
    }
    _selectionMode = false;
    _selectedDramas.clear();
    _search.text = query.trim();
    _debounce?.cancel();
    if (_search.text.isNotEmpty) {
      unawaited(
        saveUserChange(
          context,
          () => widget.store.rememberSearch(_search.text),
        ),
      );
    }
    if (_onlineSearch) {
      _load();
    } else {
      setState(() {});
    }
  }

  Future<void> _chooseCatalogView() async {
    final selected = await chooseCatalogView(context, widget.store.catalogView);
    if (selected != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setCatalogView(selected),
      );
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _openDrama(Drama drama, {bool resume = false, bool download = false}) {
    _pauseCatalog();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailScreen(
          drama: drama,
          repository: widget.repository,
          store: widget.store,
          resumeOnOpen: resume,
          downloadOnOpen: download,
        ),
      ),
    );
  }

  void _changeTab(int tab) => setState(() {
    _tab = tab;
    _selectionMode = false;
    _selectedDramas.clear();
  });

  void _onNavSelected(int tab) => _changeTab(tab);

  void _cancelSelection() => setState(() {
    _selectionMode = false;
    _selectedDramas.clear();
  });

  void _selectDrama(Drama drama) {
    if (!widget.store.canDownload ||
        !widget.repository.supportsDownloads ||
        !widget.store.allowsSource(drama.source)) {
      return;
    }
    if (!_selectedDramas.containsKey(drama.id) &&
        _selectedDramas.length >= BatchDownloads.maxDramas) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('一次最多选择 50 部短剧，请分批下载')));
      return;
    }
    setState(() {
      _selectionMode = true;
      if (_selectedDramas.remove(drama.id) == null) {
        _selectedDramas[drama.id] = drama;
      }
    });
  }

  void _downloadSelected() {
    if (!widget.store.canDownload || _selectedDramas.isEmpty) return;
    _pauseCatalog();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BatchDownloadScreen(
          repository: widget.repository,
          store: widget.store,
          dramas: _selectedDramas.values.toList(),
        ),
      ),
    );
  }

  void _dramaActions(Drama drama) => showDramaActions(
    context,
    drama: drama,
    store: widget.store,
    onContinue: () => _openDrama(drama, resume: true),
    onDownload: widget.repository.supportsDownloads && widget.store.canDownload
        ? () => _openDrama(drama, download: true)
        : null,
    onSelect: widget.repository.supportsDownloads && widget.store.canDownload
        ? () => _selectDrama(drama)
        : null,
  );

  Widget _catalogTile(
    Drama drama, {
    FocusNode? focusNode,
    VoidCallback? onFocus,
  }) {
    final following = widget.store.following(drama.id);
    final canSelect =
        widget.store.canDownload && widget.repository.supportsDownloads;
    return DramaTile(
      key: ValueKey(drama.id),
      drama: drama,
      repository: widget.repository,
      focusNode: focusNode,
      onFocus: onFocus,
      onTap: () => _selectionMode ? _selectDrama(drama) : _openDrama(drama),
      onLongPress: canSelect ? () => _selectDrama(drama) : null,
      onMore: () => _dramaActions(drama),
      actions: DramaActionButton(
        drama: drama,
        onPressed: () => _dramaActions(drama),
      ),
      selected: _selectionMode ? _selectedDramas.containsKey(drama.id) : null,
      badge: following == null
          ? null
          : '${following.status.label}${following.hasUpdates ? ' · ${following.updateLabel}' : ''}',
    );
  }

  void _pauseCatalog() {
    _debounce?.cancel();
    _generation++;
    unawaited(_browser.cancel());
    unawaited(widget.repository.cancelSuggestions());
    setState(() {
      _loading = false;
      _loadingMore = false;
    });
  }

  void _handleHomeMoreAction(String value) {
    if (value == 'update') {
      _refreshCatalog();
    } else if (value == 'sources') {
      _openSourceSwitcher();
    } else if (value == 'settings') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            repository: widget.repository,
            store: widget.store,
          ),
        ),
      );
    } else if (value == 'display') {
      _chooseDisplayMode();
    } else if (value == 'about') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AboutPage(store: widget.store),
        ),
      );
    }
  }

  Future<void> _openJsSourceManagement(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => JsSourcesPage(
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
    if (!mounted) return;
    await _loadCategories(force: true);
    await _load(force: true);
  }

  Future<void> _pickAndImportJsPlugin() async {
    final service = JsSourceService.current;
    if (service == null) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['js'],
      );
      if (file == null || !mounted) return;

      final bytes = await file.readAsBytes();
      final script = utf8.decode(bytes);
      if (script.trim().isEmpty) return;

      final fileName = file.name.endsWith('.js') ? file.name : '${file.name}.js';
      final ok = await service.importScript(script, fileName);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功导入外部插件：$fileName'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadCategories(force: true);
        await _load(force: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('插件导入失败，请检查源码是否符合规范'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入异常: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _importJsPluginFromUrl() async {
    final service = JsSourceService.current;
    if (service == null) return;

    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('网络订阅 / URL 导入插件'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请输入远程 JavaScript 插件的直接下载地址 (如 GitHub Raw 链接)：',
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '插件脚本 URL',
                  hintText: 'https://example.com/source.js',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.hongguoRed),
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) Navigator.pop(ctx, url);
            },
            child: const Text('拉取并导入'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final ok = await service.importFromUrl(result);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('成功拉取并激活远程插件'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadCategories(force: true);
        await _load(force: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('远程拉取失败，请检查链接可达性'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showPresetSelection() async {
    final service = JsSourceService.current;
    if (service == null) return;
    await showPresetSourceSelectionDialog(
      context: context,
      service: service,
      onSourceChanged: () async {
        if (!mounted) return;
        await _loadCategories(force: true);
        await _load(force: true);
      },
    );
  }

  Future<void> _importPresetPlugins() async {
    final service = JsSourceService.current;
    if (service == null) return;
    final count = await importPresetSources(service);
    if (!mounted) return;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已导入 $count 个测试数据源插件（当前测试包专用）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadCategories(force: true);
      await _load(force: true);
    }
  }

  Widget _buildEmptySourcePluginGuide(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            elevation: 0,
            color: isDark ? AppColors.darkSurface : AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.greyLight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.hongguoRed.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.extension_rounded,
                      size: 38,
                      color: AppColors.hongguoRed,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '当前未添加数据源插件',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '本应用出厂不内置任何第三方站源，请从外部导入或订阅 .js 插件。各插件在沙箱内独立运行、互不干扰。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.grey,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('btn-select-preset-import-home'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.hongguoRed,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _showPresetSelection,
                        icon: const Icon(Icons.checklist_rounded, size: 18),
                        label: const Text('选择预设源分别导入'),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _importPresetPlugins,
                        icon: const Icon(Icons.flash_on_rounded, size: 18),
                        label: const Text('一键导入全部预设'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.hongguoRed,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _pickAndImportJsPlugin,
                        icon: const Icon(Icons.file_open_rounded, size: 18),
                        label: const Text('选择外部 .js 插件'),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _importJsPluginFromUrl,
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('网络链接导入'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onPressed: () => _openJsSourceManagement(context),
                        icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                        label: const Text('插件管理'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _supportsVipFilter => false;
  bool get _hideVip => _supportsVipFilter && widget.store.hideVip;

  List<Drama> get _visible {
    final query = _search.text.trim().toLowerCase();
    return sortCatalog(
      _items.where((drama) {
        if (!widget.store.allowsSource(drama.source)) return false;
        if (_category.startsWith('local:') &&
            categoryName(drama.category) != _category.substring(6)) {
          return false;
        }
        if (_hideVip && drama.vip) {
          return false;
        }
        return _onlineSearch ||
            query.isEmpty ||
            matchesDramaQuery(drama, query);
      }),
      widget.store.catalogView,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final television = AppLayout.isTelevision(context);
        final desktop = constraints.maxWidth >= 840;
        final scaffold = Scaffold(
          appBar: HomeAppBarView(
            selectionMode: _selectionMode,
            selectedEmpty: _selectedDramas.isEmpty,
            tab: _tab,
            sourceGroups: _sourceGroups,
            group: _group,
            showRecommendations: _showRecommendations,
            searchVisible: _searchVisible,
            television: television,
            canDownload: widget.store.canDownload,
            supportsDownloads: widget.repository.supportsDownloads,
            supportsSourceManagement:
                widget.repository.supportsSourceManagement,
            sourcesEmpty: _hasNoSourcePlugins,
            loading:
                _loading ||
                _loadingMore ||
                _categoriesLoading ||
                _group.sources.any((source) => _updater.busy(source.id)),
            isUpdaterBusy: _group.sources.any(
              (source) => _updater.busy(source.id),
            ),
            catalogSortLabel: widget.store.catalogView.sort.label,
            isSortedOrFiltered:
                widget.store.catalogView.sort != CatalogSort.source ||
                widget.store.catalogView.release.isNotEmpty,
            screenWidth: constraints.maxWidth,
            onClearSelection: () => setState(_selectedDramas.clear),
            onCancelSelection: _cancelSelection,
            onChangeGroup: _changeGroup,
            onChooseCatalogView: _chooseCatalogView,
            onOpenRankings: _openRankings,
            onStartSelection: () => setState(() => _selectionMode = true),
            onToggleSearch: _toggleSearch,
            onRefreshCatalog: _refreshCatalog,
            onMoreAction: _handleHomeMoreAction,
            onOpenSourceSwitcher: _openSourceSwitcher,
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: Theme.of(context).brightness == Brightness.dark
                  ? AppGradients.darkAtmosphere
                  : null,
            ),
            child: SafeArea(
              top: false,
              child: Row(
              children: [
                if (television) ...[
                  SizedBox(
                    width: 164,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 24, 8, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in [
                            (Icons.explore_rounded, '发现'),
                            (Icons.bookmark_rounded, '追剧'),
                            (Icons.history_rounded, '最近观看'),
                            if (widget.store.canDownload)
                              (Icons.download_rounded, '下载'),
                          ].indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: RemoteButton(
                                key: ValueKey('tv-nav-${entry.$1}'),
                                label: entry.$2.$2,
                                icon: entry.$2.$1,
                                selected: _tab == entry.$1,
                                autofocus: entry.$1 == 0,
                                onPressed: () => _onNavSelected(entry.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                ] else if (desktop) ...[
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: _onNavSelected,
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: -.8,
                    destinations: [
                      NavigationRailDestination(
                        icon: Icon(Icons.explore_outlined),
                        selectedIcon: Icon(Icons.explore),
                        label: Text('发现'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.bookmark_border_rounded),
                        selectedIcon: Icon(Icons.bookmark_rounded),
                        label: Text('追剧'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.history_rounded),
                        label: Text('最近观看'),
                      ),
                      if (widget.store.canDownload)
                        NavigationRailDestination(
                          icon: Icon(Icons.download_outlined),
                          selectedIcon: Icon(Icons.download_rounded),
                          label: Text('下载'),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                ],
                Expanded(
                  child: _tab == 0
                      ? _hasNoSourcePlugins
                            ? _buildEmptySourcePluginGuide(context)
                            : _catalog(selectionInBody: desktop || television)
                      : _tab == 3
                      ? DownloadsScreen(
                          repository: widget.repository,
                          store: widget.store,
                          embedded: true,
                        )
                      : SavedLibrary(
                          key: ValueKey('saved-tab-$_tab'),
                          repository: widget.repository,
                          store: widget.store,
                          history: _tab == 2,
                          onOpen: _openDrama,
                          onContinue: (drama) =>
                              _openDrama(drama, resume: true),
                          onDownload:
                              widget.repository.supportsDownloads &&
                                  widget.store.canDownload
                              ? (drama) => _openDrama(drama, download: true)
                              : null,
                        ),
                ),
              ],
            ),
          ),
        ),
          bottomNavigationBar: desktop || television
              ? null
              : _selectionMode
              ? _selectionBar()
              : AppBottomNavigation(
                  selectedIndex: _tab,
                  onDestinationSelected: _onNavSelected,
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore),
                      label: '发现',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.bookmark_border_rounded),
                      selectedIcon: Icon(Icons.bookmark_rounded),
                      label: '追剧',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_rounded),
                      label: '最近观看',
                    ),
                    if (widget.store.canDownload)
                      NavigationDestination(
                        icon: Icon(Icons.download_outlined),
                        selectedIcon: Icon(Icons.download_rounded),
                        label: '下载',
                      ),
                  ],
                ),
        );
        if (!television && !_selectionMode) return scaffold;
        return PopScope(
          canPop:
              !_selectionMode &&
              (!television || _tab == 0 && _search.text.isEmpty),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _televisionBack();
          },
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(context).maybePop(),
              const SingleActivator(LogicalKeyboardKey.goBack): () =>
                  Navigator.of(context).maybePop(),
            },
            child: scaffold,
          ),
        );
      },
    ),
  );

  Widget _catalog({required bool selectionInBody}) {
    final items = _visible;
    final television = AppLayout.isTelevision(context);
    return Column(
      children: [
        if (_searchVisible && !television)
          HomeSearchBarView(
            groupId: _group.id,
            controller: _search,
            hint: _searchHint,
            suggestions:
                _searchSuggestions ? widget.repository.suggestions : null,
            recentSearches: widget.store.recentSearches,
            onChanged: _searchChanged,
            onCancelSuggestions: () =>
                unawaited(widget.repository.cancelSuggestions()),
            onSearch: _submitSearch,
            onClearRecentSearches: () =>
                saveUserChange(context, widget.store.clearRecentSearches),
          ),
        CatalogFilters(
          key: ValueKey('filters-${_group.id}'),
          leading: (widget.store.isZhenguojianActivated ||
                  widget.store.sources.length > 1)
              ? Padding(
                  key: const ValueKey('catalog-source-chip'),
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: Text(_group.name),
                    tooltip: '切换数据源（当前：${_group.name}）',
                    shape: const StadiumBorder(),
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    onPressed: _openSourceSwitcher,
                  ),
                )
              : null,
          categories: _displayCategories,
          category: _displayCategory,
          error: _categoriesError,
          onCategory: _changeCategory,
          onRetry: () => _loadCategories(force: true),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_supportsVipFilter)
                IconButton(
                  tooltip: widget.store.hideVip ? 'VIP：隐藏' : 'VIP：显示',
                  onPressed: () => saveUserChange(
                    context,
                    () => widget.store.setHideVip(!widget.store.hideVip),
                  ),
                  icon: VipIcon(hidden: widget.store.hideVip),
                ),
            ],
          ),
        ),
        if (_showRecommendations)
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: television ? null : _swipeCategory,
              child: RecommendationsScreen(
                repository: widget.repository,
                store: widget.store,
                embedded: true,
              ),
            ),
          )
        else ...[
          if (_loading && _items.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null && _items.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => setState(() => _error = null),
                      tooltip: '关闭提示',
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: HomeCatalogView(
              items: items,
              loading: _loading,
              loadingMore: _loadingMore,
              hasMore: _hasMore,
              error: _error,
              hideVip: _hideVip,
              television: television,
              scrollController: _scroll,
              supportsSourceManagement:
                  widget.repository.supportsSourceManagement,
              sourcesCount: widget.store.sources.length,
              canLoadMore: _hasMore &&
                  !_loadingMore &&
                  (!_onlineSearch ||
                      _search.text.isEmpty ||
                      _group.sources.any((source) => source.pagedSearch)),
              gridKey: 'catalog-${_group.id}-$_category-$_submittedQuery',
              onRetryLoad: () => _load(force: true),
              onLoadMore: () => _load(more: true),
              onRefresh: _refreshCatalog,
              onManageSources: _manageSources,
              onSwipeCategory: _swipeCategory,
              tileBuilder: _catalogTile,
            ),
          ),
          if (_selectionMode && selectionInBody)
            _selectionBar(safeBottom: false),
        ],
      ],
    );
  }

  Widget _selectionBar({bool safeBottom = true}) {
    return HomeSelectionBarView(
      selectedCount: _selectedDramas.length,
      onDownloadSelected: _downloadSelected,
      safeBottom: safeBottom,
    );
  }
}
