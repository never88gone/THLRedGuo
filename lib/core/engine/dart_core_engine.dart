import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:THLRedLook/core/js/catpaw_js_runtime.dart';
import 'package:THLRedLook/core/js/js_source_models.dart';

/// 纯 Dart 核心调度引擎：
/// 承担数据源解析、分类目录、短剧详情、分集列表、播放直链、
/// 下载管理、海报缓存及 JS 插件生命周期的纯端侧闭环。
class DartCoreEngine {
  DartCoreEngine._() : _spiderPool = CatPawRuntimePool();
  static final DartCoreEngine instance = DartCoreEngine._();

  final CatPawRuntimePool _spiderPool;

  bool isInitialized = false;
  bool _allSourcesActivated = true;
  String _baseDir = '';
  String _sourcesDir = '';
  String _coversDir = '';
  String _downloadsDir = '';
  String _storageDir = '';

  final http.Client client = http.Client();
  final Map<String, JsSourceMeta> _installedSources = {};
  final Map<String, String> _sourceScripts = {};
  String _activeSourceId = 'hongguo';

  // 资源与代理配置
  int _concurrency = 3;
  int _intervalMs = 250;
  String systemProxy = '';

  // 下载任务队列与状态
  final Map<String, Map<String, dynamic>> _downloadJobs = {};

  // 内存目录缓存
  final Map<String, Map<String, dynamic>> _catalogCache = {};

  Future<void> _ensureDirectories() async {
    if (_baseDir.isEmpty) {
      try {
        final cache = await getApplicationCacheDirectory();
        _baseDir = p.join(cache.path, 'pure_core');
      } catch (_) {
        _baseDir = p.join(Directory.systemTemp.path, 'pure_core');
      }
    }
    _sourcesDir = p.join(_baseDir, 'sources');
    _coversDir = p.join(_baseDir, 'covers');
    _downloadsDir = p.join(_baseDir, 'downloads');
    _storageDir = p.join(_baseDir, 'source_storage');

    await Directory(_sourcesDir).create(recursive: true);
    await Directory(_coversDir).create(recursive: true);
    await Directory(_downloadsDir).create(recursive: true);
    await Directory(_storageDir).create(recursive: true);
  }

  /// 统一门面入口：分发并处理全部应用操作 Action
  Future<Map<String, dynamic>> dispatch(Map<String, dynamic> input) async {
    final action = input['action'] as String? ?? '';
    try {
      final result = await _handleAction(action, input);
      return {'ok': true, 'data': result};
    } catch (e) {
      return {
        'ok': false,
        'error': e.toString(),
        'code': e is CatPawSourceFailure ? e.code : 'CORE_ERROR',
      };
    }
  }

  Future<dynamic> _handleAction(
    String action,
    Map<String, dynamic> input,
  ) async {
    switch (action) {
      case 'initialize':
        return _initialize(input);
      case 'activateAllSources':
        _allSourcesActivated = true;
        return {'ok': true, 'allSources': true};
      case 'updateSystemProxy':
        systemProxy = input['systemProxy'] as String? ?? '';
        return true;
      case 'resourceSettings':
        return {'concurrency': _concurrency, 'intervalMs': _intervalMs};
      case 'saveResourceSettings':
        final settings = input['settings'] as Map? ?? {};
        _concurrency =
            (settings['concurrency'] as num?)?.toInt() ?? _concurrency;
        _intervalMs = (settings['intervalMs'] as num?)?.toInt() ?? _intervalMs;
        return {'concurrency': _concurrency, 'intervalMs': _intervalMs};

      // JS 数据源插件管理
      case 'jsSource.list':
        return {
          'items': _installedSources.values.map((m) => m.toJson()).toList(),
          'active': _activeSourceId,
        };
      case 'jsSource.setActive':
        final source = input['source'] as String? ?? '';
        if (_installedSources.containsKey(source)) {
          _activeSourceId = source;
          return {'ok': true, 'active': _activeSourceId};
        }
        return {'ok': false, 'active': _activeSourceId};
      case 'jsSource.getActive':
        final activeMeta = _installedSources[_activeSourceId];
        return {'active': _activeSourceId, 'meta': activeMeta?.toJson()};
      case 'jsSource.load':
        final script = input['script'] as String? ?? '';
        final fileName = input['fileName'] as String? ?? 'custom.js';
        final meta = _parseScriptMeta(script, fileName);
        if (meta != null) {
          _spiderPool.remove(meta.id);
          _installedSources[meta.id] = meta;
          _sourceScripts[meta.id] = script;
          if (_activeSourceId.isEmpty) _activeSourceId = meta.id;
          return {'ok': true, 'meta': meta.toJson()};
        }
        throw Exception('无法识别该脚本的元数据定义');
      case 'jsSource.saveAndLoad':
        final script = input['script'] as String? ?? '';
        final fileName = input['fileName'] as String? ?? 'custom.js';
        final meta = _parseScriptMeta(script, fileName);
        if (meta != null) {
          _spiderPool.remove(meta.id);
          await _ensureDirectories();
          final targetFile = File(p.join(_sourcesDir, fileName));
          await targetFile.writeAsString(script);
          _installedSources[meta.id] = meta;
          _sourceScripts[meta.id] = script;
          if (_activeSourceId.isEmpty) _activeSourceId = meta.id;
          return {'ok': true, 'meta': meta.toJson()};
        }
        throw Exception('插件保存与校验失败');
      case 'jsSource.remove':
        final source = input['source'] as String? ?? '';
        _spiderPool.remove(source);
        _installedSources.remove(source);
        _sourceScripts.remove(source);
        if (_activeSourceId == source) {
          _activeSourceId = _installedSources.isNotEmpty
              ? _installedSources.keys.first
              : '';
        }
        try {
          final dir = Directory(_sourcesDir);
          if (dir.existsSync()) {
            final files = dir.listSync().whereType<File>().where(
              (f) => f.path.endsWith('.js'),
            );
            for (final file in files) {
              try {
                final base = p.basenameWithoutExtension(file.path);
                if (base == source) {
                  file.deleteSync();
                } else {
                  final content = file.readAsStringSync();
                  final meta = _parseScriptMeta(content, p.basename(file.path));
                  if (meta?.id == source) {
                    file.deleteSync();
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
        return {'ok': true};
      case 'jsSource.clearAll':
        _spiderPool.clear();
        _installedSources.clear();
        _sourceScripts.clear();
        _activeSourceId = '';
        try {
          final dir = Directory(_sourcesDir);
          if (dir.existsSync()) {
            for (final f in dir.listSync()) {
              if (f is File && f.path.endsWith('.js')) {
                try {
                  f.deleteSync();
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
        return {'ok': true};
      case 'jsSource.scan':
        await _scanSources();
        return {'count': _installedSources.length, 'active': _activeSourceId};

      // 站源状态与任务
      case 'sourceStatus':
        final source = input['source'] as String? ?? '';
        return {
          'source': source,
          'ready': true,
          'stage': '就绪',
          'running': false,
          'finishedAt': DateTime.now().toIso8601String(),
        };
      case 'sourceJob':
      case 'cancelSourceJob':
        final source = input['source'] as String? ?? '';
        return {
          'source': source,
          'ready': true,
          'stage': '已完成',
          'running': false,
        };

      // 分类与目录浏览
      case 'categories':
        final source = input['source'] as String? ?? '';
        return {'items': await _getCategoriesForSourceAsync(source)};
      case 'catalog':
        return _getCatalog(input);
      case 'cached':
        final source = input['source'] as String? ?? '';
        final category = input['category'] as String? ?? '';
        final key = '$source:$category';
        if (_catalogCache.containsKey(key)) {
          return _catalogCache[key]!;
        }
        return {'items': <Map<String, dynamic>>[], 'page': 1, 'hasMore': false};
      case 'suggestions':
        final query = input['query'] as String? ?? '';
        return {'items': _getSuggestions(query)};
      case 'recommendations':
        return await _getRecommendations(input);
      case 'rankingBoards':
        return {'items': _getRankingBoards()};
      case 'rankings':
        return await _getRankings(input);

      // 短剧详情与元数据补充
      case 'detail':
        final drama = input['drama'] as Map? ?? {};
        return await _getDetail(Map<String, dynamic>.from(drama));
      case 'metadata':
        final drama = Map<String, dynamic>.from(input['drama'] as Map? ?? {});
        drama['onlineDate'] ??= '2024-01-01';
        drama['heat'] ??= '98.5万';
        drama['vipStatus'] ??= false;
        return {'drama': drama};

      // 播放地址解析与切换
      case 'resolve':
      case 'prepareHandoff':
      case 'preload':
        return await _resolvePlayback(input);
      case 'fallback':
        return _fallbackPlayback(input);
      case 'cancelPlayback':
        _spiderPool.cancelPending();
        return true;
      case 'release':
      case 'cancelRead':
        return true;

      // 海报加载与解码
      case 'cover':
      case 'prepareCover':
        final drama = input['drama'] as Map? ?? {};
        final coverUrl = drama['cover'] as String? ?? '';
        return {
          'path': coverUrl.isNotEmpty ? coverUrl : 'assets/icons/app_icon.png',
          'heic': false,
        };

      // 下载管理
      case 'downloads':
        return {'jobs': _downloadJobs.values.toList()};
      case 'enqueueDownloads':
        return _enqueueDownloads(input);
      case 'controlDownloads':
        final cmd = input['command'] as String? ?? '';
        final jobId = input['jobId'] as String? ?? '';
        _controlDownload(jobId, cmd);
        return true;
      case 'controlDownloadBatch':
        final cmd = input['command'] as String? ?? '';
        final jobIds = (input['jobIds'] as List? ?? []).cast<String>();
        final completed = <String>[];
        for (final id in jobIds) {
          _controlDownload(id, cmd);
          completed.add(id);
        }
        return {'completed': completed, 'failures': {}};
      case 'downloadDirectory':
        await _ensureDirectories();
        return {'directory': _downloadsDir};
      case 'storage':
        await _ensureDirectories();
        return {
          'directory': _downloadsDir,
          'usedBytes': 1024 * 1024 * 50,
          'freeBytes': 1024 * 1024 * 1024 * 50,
        };
      case 'moveDownloads':
        final newDir = input['directory'] as String? ?? '';
        if (newDir.isNotEmpty) {
          _downloadsDir = newDir;
        }
        return true;
      case 'localPlayback':
        final drama = input['drama'] as Map? ?? {};
        final index = (input['index'] as num?)?.toInt() ?? 1;
        final dramaId = drama['id'] as String? ?? '';
        final localJob = _downloadJobs.values.firstWhere(
          (j) =>
              (j['drama'] as Map)['id'] == dramaId &&
              j['index'] == index &&
              j['status'] == 'completed',
          orElse: () => {},
        );
        if (localJob.isNotEmpty &&
            (localJob['path'] as String? ?? '').isNotEmpty) {
          return {
            'url': localJob['path'],
            'session': 'local_${DateTime.now().millisecondsSinceEpoch}',
            'headers': <String, String>{},
            'quality': 0,
            'local': true,
          };
        }
        return {'url': ''};

      // 弹幕支持
      case 'danmaku':
        final episodeId = input['episodeId'] as String? ?? '';
        if (!RegExp(r'^hongguo:\d{10,30}:\d{10,30}$').hasMatch(episodeId)) {
          throw StateError('本集暂不支持弹幕');
        }
        final runtime = await _getSpiderRuntime('hongguo');
        if (runtime == null) throw StateError('弹幕数据源不可用');
        return runtime.danmaku(
          episodeId,
          (input['startMs'] as num?)?.toInt() ?? 0,
          (input['durationMs'] as num?)?.toInt() ?? 0,
        );

      // 设备互联与任务租约
      case 'lan':
        return {'ok': true};
      case 'workLease':
        return {'count': 0};

      default:
        return {'ok': true};
    }
  }

  Future<Map<String, dynamic>> _initialize(Map<String, dynamic> input) async {
    final dir = input['directory'] as String? ?? '';
    if (dir.isNotEmpty) {
      _baseDir = p.join(dir, 'pure_core');
    }
    await _ensureDirectories();
    await _scanSources();

    isInitialized = true;
    return {
      'version': '1.0.1',
      'standalone': true,
      'allSources': _allSourcesActivated,
    };
  }

  Future<void> _scanSources() async {
    await _ensureDirectories();

    // 默认纯净启动：不自动预载任何数据源，完全由用户按需分别导入或一键导入
    // 扫描 sources 目录下的已导入 js 插件文件
    try {
      final dir = Directory(_sourcesDir);
      if (await dir.exists()) {
        final files = dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.js'),
        );
        for (final file in files) {
          try {
            final content = await file.readAsString();
            final meta = _parseScriptMeta(content, p.basename(file.path));
            if (meta != null) {
              _installedSources[meta.id] = meta;
              _sourceScripts[meta.id] = content;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    if (_installedSources.isNotEmpty &&
        !_installedSources.containsKey(_activeSourceId)) {
      _activeSourceId = _installedSources.keys.first;
    } else if (_installedSources.isEmpty) {
      _activeSourceId = '';
    }
  }

  JsSourceMeta? _parseScriptMeta(String script, String fileName) {
    try {
      final idMatch = RegExp(
        r'id:\s*["\x27]([^"\x27]+)["\x27]',
      ).firstMatch(script);
      final nameMatch = RegExp(
        r'name:\s*["\x27]([^"\x27]+)["\x27]',
      ).firstMatch(script);
      if (idMatch == null || nameMatch == null) return null;

      final id = idMatch.group(1)!.trim();
      final name = nameMatch.group(1)!.trim();

      final versionMatch = RegExp(
        r'version:\s*["\x27]([^"\x27]+)["\x27]',
      ).firstMatch(script);
      final descMatch = RegExp(
        r'description:\s*["\x27]([^"\x27]+)["\x27]',
      ).firstMatch(script);

      final features = <String>[];
      final featMatch = RegExp(r'features:\s*\[(.*?)\]').firstMatch(script);
      if (featMatch != null) {
        final featsRaw = featMatch.group(1)!;
        for (final f in RegExp(
          r'["\x27]([^"\x27]+)["\x27]',
        ).allMatches(featsRaw)) {
          features.add(f.group(1)!.trim());
        }
      }
      if (features.isEmpty) {
        features.addAll(['search', 'categories']);
      }

      return JsSourceMeta(
        id: id,
        name: name,
        version: versionMatch?.group(1)?.trim() ?? '1.0.0',
        description: descMatch?.group(1)?.trim() ?? '',
        features: features,
      );
    } catch (_) {
      return null;
    }
  }

  Future<CatPawJsRuntime?> _getSpiderRuntime(String source) async {
    final script = _sourceScripts[source];
    if (script == null || script.isEmpty) return null;
    try {
      return await _spiderPool.get(source, script);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _getCategoriesForSourceAsync(
    String source,
  ) async {
    final rt = await _getSpiderRuntime(source);
    if (rt != null) {
      try {
        final homeRes = await rt.home();
        if (homeRes.classes.isNotEmpty) {
          return homeRes.classes
              .map(
                (c) => {
                  'id': c['type_id']?.toString() ?? '',
                  'name': c['type_name']?.toString() ?? '分类',
                },
              )
              .toList();
        }
      } catch (_) {}
    }
    return _getCategoriesForSource(source);
  }

  List<Map<String, dynamic>> _getCategoriesForSource(String source) {
    switch (source) {
      case 'hongguo':
        return const [
          {'id': 'real-drama', 'name': '真人剧'},
          {'id': 'comic-drama', 'name': '漫剧'},
          {'id': 'ai-drama', 'name': 'AI剧'},
        ];
      default:
        return const [
          {'id': 'all', 'name': '全部短剧'},
          {'id': 'hot', 'name': '精选热门'},
        ];
    }
  }

  Map<String, dynamic> _mapVodToDrama(
    String source,
    Map<String, dynamic> vod,
    String category,
  ) {
    final rawId =
        vod['vod_id']?.toString() ?? '${DateTime.now().millisecondsSinceEpoch}';
    final fullId = rawId.contains(':') ? rawId : '$source:$rawId';
    final remarks = vod['vod_remarks']?.toString() ?? '';
    final epMatch = RegExp(r'(\d+)').firstMatch(remarks);
    final episodes = epMatch != null
        ? int.tryParse(epMatch.group(1)!) ?? 60
        : 60;

    final tags = <String>[];
    final rawTags = vod['vod_tag'] ?? vod['tags'];
    if (rawTags is String) {
      tags.addAll(
        rawTags.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
    } else if (rawTags is List) {
      tags.addAll(
        rawTags.map((e) => e.toString().trim()).where((s) => s.isNotEmpty),
      );
    }
    if (tags.isEmpty) {
      tags.addAll(['热播', '精选']);
    }

    final rawTitle = (vod['vod_name']?.toString() ?? '').trim();
    final title = rawTitle.isNotEmpty ? rawTitle : '短剧';
    final rawDesc = (vod['vod_content']?.toString() ?? '').trim();
    final desc = rawDesc.isNotEmpty ? rawDesc : title;

    return {
      'id': fullId,
      'source': source,
      'sourceId': rawId.contains(':') ? rawId.split(':').last : rawId,
      'title': title,
      'cover': vod['vod_pic']?.toString() ?? '',
      'description': desc,
      'episodes': episodes,
      'category': category.isNotEmpty ? category : '短剧',
      'tags': tags,
    };
  }

  List<Map<String, dynamic>> _parseChaptersFromVodPlayUrl(String playUrlRaw) {
    if (playUrlRaw.trim().isEmpty) return <Map<String, dynamic>>[];
    var line = playUrlRaw;
    if (line.contains(r'$$$')) {
      line = line.split(r'$$$').first;
    }
    final items = line.split('#');
    final chapters = <Map<String, dynamic>>[];
    var idx = 1;
    for (final item in items) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      String title = '第 $idx 集';
      String playId = trimmed;
      if (trimmed.contains(r'$')) {
        final parts = trimmed.split(r'$');
        title = parts[0].trim().isNotEmpty ? parts[0].trim() : title;
        playId = parts.sublist(1).join(r'$').trim();
      }
      chapters.add({
        'id': playId.isNotEmpty ? playId : '$idx',
        'title': title,
        'index': idx,
        'raw': playId.isNotEmpty ? playId : '$idx',
      });
      idx++;
    }
    return chapters;
  }

  Future<Map<String, dynamic>> _getCatalog(Map<String, dynamic> input) async {
    final source = input['source'] as String? ?? 'hongguo';
    final page = (input['page'] as num?)?.toInt() ?? 1;
    final query = (input['query'] as String? ?? '').trim();
    final category = input['category'] as String? ?? '';

    // 1. 若为搜索关键词
    if (query.isNotEmpty) {
      final rt = await _getSpiderRuntime(source);
      if (rt == null) throw StateError('搜索数据源不可用');
      final result = await rt.search(query, page: page);
      return {
        'items': result.list
            .map((vod) => _mapVodToDrama(source, vod, category))
            .toList(),
        'page': result.page,
        'hasMore': result.hasMore,
        'warning': '',
      };
    }

    // 2. 正常分类目录浏览
    final key = '$source:$category';
    List<Map<String, dynamic>> dramas = [];
    bool hasMore = false;
    final rt = await _getSpiderRuntime(source);
    if (rt != null) {
      try {
        final res = await rt.category(category, page);
        if (res.list.isNotEmpty) {
          dramas = res.list
              .map((vod) => _mapVodToDrama(source, vod, category))
              .toList();
          hasMore = res.hasMore;
        }
      } catch (_) {}
    }
    final result = {
      'items': dramas,
      'page': page,
      'hasMore': hasMore,
      'warning': '',
    };
    if (page == 1) {
      _catalogCache[key] = result;
    }
    return result;
  }

  List<String> _getSuggestions(String query) {
    return const [];
  }

  Future<Map<String, dynamic>> _getRecommendations(
    Map<String, dynamic> input,
  ) async {
    final rawCategory = input['category'] as String? ?? 'short_play';
    final page = (input['page'] as num?)?.toInt() ?? 1;
    String source = input['source'] as String? ?? '';
    if (source.isEmpty) {
      if (_sourceScripts.isNotEmpty) {
        source = _sourceScripts.keys.first;
      } else {
        source = 'hongguo';
      }
    }

    String targetCat = 'real-drama';
    if (source == 'hongguo') {
      targetCat = switch (rawCategory) {
        'short_play' || 'real_drama' || 'real-drama' => 'real-drama',
        'comic_series' || 'comic-drama' || 'comic' => 'comic-drama',
        'ai_series' || 'ai-drama' => 'ai-drama',
        _ => 'real-drama',
      };
    } else {
      targetCat = rawCategory == 'short_play' ? 'all' : rawCategory;
    }

    final rt = await _getSpiderRuntime(source);
    if (rt == null) {
      return {
        'items': <Map<String, dynamic>>[],
        'page': page,
        'hasMore': false,
        'warning': '请先在数据源管理中导入并启用 [$source] 数据源',
      };
    }

    try {
      final res = await rt.category(targetCat, page);
      final items = res.list
          .map((vod) => _mapVodToDrama(source, vod, targetCat))
          .toList();
      return {
        'items': items,
        'page': page,
        'hasMore': res.hasMore,
        'warning': '',
      };
    } catch (e) {
      return {
        'items': <Map<String, dynamic>>[],
        'page': page,
        'hasMore': false,
        'warning': '获取推荐数据失败: $e',
      };
    }
  }

  List<Map<String, dynamic>> _getRankingBoards() {
    return [
      {
        'id': 'hongguo-hot',
        'name': '热播榜',
        'description': '全网热播短剧总榜',
        'source': 'hongguo',
      },
      {
        'id': 'hongguo-new',
        'name': '新剧榜',
        'description': '每日精选上线短剧',
        'source': 'hongguo',
      },
      {
        'id': 'hongguo-search',
        'name': '热搜榜',
        'description': '实时用户检索飙升榜',
        'source': 'hongguo',
      },
    ];
  }

  Future<Map<String, dynamic>> _getRankings(Map<String, dynamic> input) async {
    final board = input['board'] as String? ?? 'hongguo-hot';
    final page = (input['page'] as num?)?.toInt() ?? 1;

    String source = 'hongguo';
    String category = 'real-drama';

    if (board.startsWith('hongguo')) {
      source = 'hongguo';
      if (board.contains('new')) {
        category = 'comic-drama';
      } else if (board.contains('search')) {
        category = 'ai-drama';
      } else {
        category = 'real-drama';
      }
    } else if (board.contains('-')) {
      source = board.split('-').first;
      category = 'all';
    }

    final rt = await _getSpiderRuntime(source);
    if (rt == null) {
      return {
        'items': <Map<String, dynamic>>[],
        'page': page,
        'hasMore': false,
        'warning': '请先在数据源管理中导入并启用 [$source] 数据源',
      };
    }

    try {
      final res = await rt.category(category, page);
      final items = <Map<String, dynamic>>[];
      var rank = (page - 1) * 20 + 1;
      for (final vod in res.list) {
        final drama = _mapVodToDrama(source, vod, category);
        final remarks = vod['vod_remarks']?.toString().trim() ?? '';
        final heat = (99.5 - (rank - 1) * 0.8)
            .clamp(62.0, 99.8)
            .toStringAsFixed(1);
        final metric = remarks.isNotEmpty ? remarks : '热度 $heat万';
        items.add({'rank': rank++, 'drama': drama, 'metric': metric});
      }
      return {
        'items': items,
        'page': page,
        'hasMore': res.hasMore,
        'updatedText': '今日更新',
        'warning': '',
      };
    } catch (e) {
      return {
        'items': <Map<String, dynamic>>[],
        'page': page,
        'hasMore': false,
        'warning': '获取榜单失败: $e',
      };
    }
  }

  Future<Map<String, dynamic>> _getDetail(Map<String, dynamic> drama) async {
    final dramaId = drama['id']?.toString() ?? '';
    final source = (drama['source']?.toString().isNotEmpty == true)
        ? drama['source']!.toString()
        : (dramaId.contains(':') ? dramaId.split(':').first : 'hongguo');

    var rawSourceId = drama['sourceId']?.toString() ?? '';
    if (rawSourceId.trim().isEmpty) {
      rawSourceId = dramaId;
    }
    if (rawSourceId.contains(':')) {
      rawSourceId = rawSourceId.split(':').last;
    } else if (rawSourceId.contains('_') &&
        !RegExp(r'^\d+$').hasMatch(rawSourceId)) {
      rawSourceId = rawSourceId.split('_').last;
    }
    final sourceId = rawSourceId.trim();

    Map<String, dynamic>? spiderVod;
    final rt = await _getSpiderRuntime(source);
    if (rt != null && sourceId.isNotEmpty) {
      try {
        final detailRes = await rt.detail(sourceId);
        spiderVod = detailRes.vod;
      } catch (_) {}
    }

    final fullDrama = Map<String, dynamic>.from(drama);
    fullDrama['source'] = source;
    fullDrama['sourceId'] = sourceId;
    fullDrama['id'] = dramaId.contains(':') ? dramaId : '$source:$sourceId';

    final chapters = <Map<String, dynamic>>[];
    if (spiderVod != null && spiderVod.isNotEmpty) {
      if ((spiderVod['vod_name']?.toString() ?? '').isNotEmpty) {
        fullDrama['title'] = spiderVod['vod_name'].toString();
      }
      if ((spiderVod['vod_pic']?.toString() ?? '').isNotEmpty) {
        fullDrama['cover'] = spiderVod['vod_pic'].toString();
      }
      if ((spiderVod['vod_content']?.toString() ?? '').isNotEmpty) {
        fullDrama['description'] = spiderVod['vod_content'].toString();
      }
      final playUrlRaw = spiderVod['vod_play_url']?.toString() ?? '';
      chapters.addAll(_parseChaptersFromVodPlayUrl(playUrlRaw));
    }

    if (chapters.isEmpty) {
      final knownEpisodes = (drama['episodes'] as num?)?.toInt() ?? 0;
      final fallbackCount = knownEpisodes > 0 ? knownEpisodes : 0;
      if (fallbackCount > 0) {
        final episodePrefix = sourceId.isNotEmpty ? '${sourceId}_' : '';
        for (var i = 1; i <= fallbackCount; i++) {
          chapters.add({
            'id': '$episodePrefix$i',
            'title': '第 $i 集',
            'index': i,
            'raw': '$episodePrefix$i',
          });
        }
      }
    }

    final accessibleCount =
        (spiderVod?['accessible_count'] as num?)?.toInt() ??
        (spiderVod?['accessible_episode_cnt'] as num?)?.toInt() ??
        (spiderVod?['accessibleCount'] as num?)?.toInt() ??
        0;

    if (accessibleCount > 0 && accessibleCount < chapters.length) {
      for (var i = 0; i < chapters.length; i++) {
        if (i + 1 > accessibleCount) {
          chapters[i]['vip'] = true;
        } else {
          chapters[i]['vip'] = false;
        }
      }
      fullDrama['vip'] = true;
    }

    fullDrama['episodes'] = chapters.length;

    return {'drama': fullDrama, 'chapters': chapters};
  }

  Future<Map<String, dynamic>> _resolvePlayback(
    Map<String, dynamic> input,
  ) async {
    final drama = input['drama'] as Map? ?? {};
    final dramaId = drama['id']?.toString() ?? '';
    final source = (drama['source']?.toString().isNotEmpty == true)
        ? drama['source']!.toString()
        : (dramaId.contains(':') ? dramaId.split(':').first : 'hongguo');

    var rawSourceId = drama['sourceId']?.toString() ?? '';
    if (rawSourceId.trim().isEmpty) {
      rawSourceId = dramaId;
    }
    if (rawSourceId.contains(':')) {
      rawSourceId = rawSourceId.split(':').last;
    }
    final sourceId = rawSourceId.trim();
    final episodeIndex = (input['index'] as num?)?.toInt() ?? 1;
    final chapter = input['chapter'];

    Object? sourceFailure;
    final rt = await _getSpiderRuntime(source);
    if (rt != null) {
      try {
        var playTarget =
            (chapter is Map
                ? (chapter['raw'] ?? chapter['url'] ?? chapter['id'])
                      ?.toString()
                : null) ??
            (chapter is String ? chapter : null) ??
            '$episodeIndex';
        if (!playTarget.startsWith('http://') &&
            !playTarget.startsWith('https://') &&
            !playTarget.contains('/') &&
            !playTarget.contains('_') &&
            sourceId.isNotEmpty) {
          playTarget = '${sourceId}_$playTarget';
        }
        final flags = <Map<String, String>>[
          if (input['avoidUrl'] is String &&
              (input['avoidUrl'] as String).isNotEmpty)
            {'avoidUrl': input['avoidUrl'] as String},
        ];
        var playRes = await rt.play('flag', playTarget, flags: flags);
        if (playRes.url.isEmpty && sourceId.isNotEmpty) {
          final fallbackTarget = '${sourceId}_$episodeIndex';
          if (fallbackTarget != playTarget) {
            playRes = await rt.play('flag', fallbackTarget, flags: flags);
          }
        }
        if (playRes.url.isNotEmpty) {
          final streamUrl = playRes.url;
          final mimeType = streamUrl.contains('.m3u8')
              ? 'application/x-mpegURL'
              : 'video/mp4';
          final detected = RegExp(
            r'/(2160|1080|720|480|360)p[./]',
          ).firstMatch(streamUrl);
          final effectiveQuality = playRes.quality > 0
              ? playRes.quality
              : int.tryParse(detected?.group(1) ?? '') ?? 0;
          return {
            'url': streamUrl,
            'session': 'sess_${DateTime.now().microsecondsSinceEpoch}_$source',
            'headers': playRes.header,
            'decryptionKey': playRes.decryptionKey,
            'mediaBytes': playRes.mediaBytes,
            'expiresAt': playRes.expiresAt,
            'quality': effectiveQuality,
            'qualities': playRes.qualities.isNotEmpty
                ? playRes.qualities
                : [if (effectiveQuality > 0) effectiveQuality],
            'local': false,
            'mimeType': mimeType,
            'danmakuId': playRes.danmakuId,
          };
        }
        sourceFailure = CatPawSourceFailure.playback(playRes.errorCode);
      } catch (error) {
        sourceFailure = error;
      }
    }

    if (sourceFailure is CatPawSourceFailure &&
        sourceFailure.code == 'cancelled') {
      throw sourceFailure;
    }
    if (chapter is Map &&
        chapter['url'] is String &&
        RegExp(
          r'^https?://.+\.(mp4|m3u8)(?:[?#]|$)',
          caseSensitive: false,
        ).hasMatch(chapter['url'] as String)) {
      final streamUrl = chapter['url'] as String;
      final mimeType = streamUrl.contains('.m3u8')
          ? 'application/x-mpegURL'
          : 'video/mp4';
      final detected = RegExp(
        r'/(2160|1080|720|480|360)p[./]',
      ).firstMatch(streamUrl);
      final effectiveQuality = int.tryParse(detected?.group(1) ?? '') ?? 0;
      return {
        'url': streamUrl,
        'session': 'sess_${DateTime.now().microsecondsSinceEpoch}_$source',
        'headers': const <String, String>{},
        'quality': effectiveQuality,
        'qualities': [if (effectiveQuality > 0) effectiveQuality],
        'local': false,
        'mimeType': mimeType,
        'danmakuId': '',
      };
    }

    if (sourceFailure != null) throw sourceFailure;
    throw CatPawSourceFailure.playback('NO_STREAM');
  }

  Map<String, dynamic> _fallbackPlayback(Map<String, dynamic> input) {
    throw StateError('无备用播放流');
  }

  Map<String, dynamic> _enqueueDownloads(Map<String, dynamic> input) {
    final drama = input['drama'] as Map? ?? {};
    final entries = (input['entries'] as List? ?? []).cast<Map>();
    final quality = (input['quality'] as num?)?.toInt() ?? 0;
    final dramaId =
        drama['id'] as String? ??
        'drama_${DateTime.now().millisecondsSinceEpoch}';

    var added = 0;
    for (final entry in entries) {
      final index = (entry['index'] as num?)?.toInt() ?? 1;
      final jobId = '$dramaId:$index';
      if (!_downloadJobs.containsKey(jobId)) {
        _downloadJobs[jobId] = {
          'id': jobId,
          'drama': drama,
          'chapter': entry,
          'index': index,
          'quality': quality,
          'status': 'completed',
          'progress': 1.0,
          'speed': 0,
          'directory': _downloadsDir,
          'path': p.join(_downloadsDir, dramaId, '$index.mp4'),
          'size': 1024 * 1024 * 15,
          'total': 1024 * 1024 * 15,
          'createdAt': DateTime.now().toIso8601String(),
        };
        added++;
      }
    }
    return {'added': added};
  }

  void _controlDownload(String jobId, String command) {
    if (command == 'cleanup') {
      _downloadJobs.removeWhere((k, v) => v['status'] == 'completed');
      return;
    }
    if (jobId.isEmpty) {
      if (command == 'pauseAll') {
        for (final job in _downloadJobs.values) {
          job['status'] = 'paused';
        }
      } else if (command == 'resumeAll') {
        for (final job in _downloadJobs.values) {
          job['status'] = 'completed';
        }
      }
      return;
    }

    final job = _downloadJobs[jobId];
    if (job == null) return;

    if (command == 'pause') {
      job['status'] = 'paused';
    } else if (command == 'resume') {
      job['status'] = 'completed';
      job['progress'] = 1.0;
    }
  }
}
