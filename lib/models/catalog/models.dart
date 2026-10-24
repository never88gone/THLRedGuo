import 'dart:convert';

import 'package:THLRedLook/utils/build/app_build.dart';
import 'package:THLRedLook/core/js/js_source_service.dart';
import 'package:THLRedLook/utils/media/cover_decoder.dart';

class SourceSite {
  const SourceSite(this.id, this.name, this.description);
  final String id;
  final String name;
  final String description;
  bool get onlineSearch => id == 'hongguo';
  bool get pagedSearch => id == 'hongguo';
  bool get searchSuggestions => id == 'hongguo';
  String get groupId => id;
  String get groupName => name;
  String get entryName => name;

  static const hongguo = SourceSite('hongguo', '精选短剧', '短剧 · 漫剧 · AI 剧');

  /// 默认可见站源：开源版本仅包含官方规范短剧
  static const primaryValues = [hongguo];

  /// 敏感站源：开源版本已全部移除
  static const restrictedValues = <SourceSite>[];
  static const knownValues = [hongguo];
  static const allValues = [hongguo];

  static bool _runtimeActivated = false;

  /// 是否已激活全功能模式（编译开关打开或运行时用户激活）。
  static bool get isZhenguojianActivated =>
      allSourcesEnabled || _runtimeActivated;

  /// 运行时激活全功能模式，解锁全部数据源。
  static void activateAllSources() => _runtimeActivated = true;

  /// 重置运行时激活状态（主要供测试使用）。
  static void resetRuntimeActivation() => _runtimeActivated = false;

  static List<SourceSite> get values {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return [
        for (final meta in jsService.sources)
          SourceSite(meta.id, meta.name, meta.description),
      ];
    }
    final baseSites = isZhenguojianActivated ? knownValues : const [hongguo];
    return baseSites;
  }

  static bool isAvailable(String id) {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return jsService.sources.any((s) => s.id == id);
    }
    return values.any((site) => site.id == id) ||
        allValues.any((site) => site.id == id);
  }

  static bool isKnown(String id) {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return jsService.sources.any((s) => s.id == id);
    }
    return values.any((site) => site.id == id) ||
        allValues.any((site) => site.id == id);
  }

  static bool isPrimary(String id) {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return jsService.sources.any((s) => s.id == id);
    }
    return primaryValues.any((site) => site.id == id);
  }

  static bool isRestricted(String id) =>
      restrictedValues.any((site) => site.id == id);

  /// 运行时可见站源：当启用 JS 服务时完全取决于已导入的 JS 插件；无插件时返回空列表
  static List<SourceSite> visibleValues({required bool unlocked}) {
    final jsService = JsSourceService.current;
    if (jsService != null) {
      return [
        for (final meta in jsService.sources)
          SourceSite(meta.id, meta.name, meta.description),
      ];
    }
    return [
      for (final site
          in (unlocked || isZhenguojianActivated ? knownValues : primaryValues))
        site,
    ];
  }

  static SourceSite byId(String id) {
    final jsSources = JsSourceService.current?.sources;
    if (jsSources != null) {
      for (final meta in jsSources) {
        if (meta.id == id) {
          return SourceSite(meta.id, meta.name, meta.description);
        }
      }
    }
    for (final site in allValues) {
      if (site.id == id) return site;
    }
    return SourceSite(id, id, '自定义数据源');
  }
}

class SourceGroup {
  const SourceGroup(this.id, this.name, this.sources);
  final String id;
  final String name;
  final List<SourceSite> sources;

  static List<SourceGroup> fromSources(Iterable<SourceSite> sources) {
    final groups = <String, List<SourceSite>>{};
    for (final source in sources) {
      (groups[source.groupId] ??= []).add(source);
    }
    return [
      for (final group in groups.entries)
        SourceGroup(group.key, group.value.first.groupName, group.value),
    ];
  }
}

class CatalogCategory {
  const CatalogCategory(this.id, this.name, {this.local = false});
  static const all = CatalogCategory('', '全部');
  final String id;
  final String name;
  final bool local;
  factory CatalogCategory.fromJson(Map<String, dynamic> json) =>
      CatalogCategory(
        json['id'] as String? ?? '',
        json['name'] as String? ?? '全部',
      );
}

String dramaCategoryLabel(String value) {
  final category = value.trim();
  if (category.startsWith('app:discover:')) {
    return switch (category.split(':').last) {
      'playlet' => '真人剧',
      'motion_comic' => '漫剧',
      'ai_playlet' => 'AI剧',
      _ => '短剧',
    };
  }
  if (category.startsWith('app:') || category.startsWith('hongguo-app:')) {
    return '短剧';
  }
  return switch (category) {
    'real-drama' || 'real_series' => '真人剧',
    'comic-drama' || 'comic_series' || 'comic' => '漫剧',
    'ai-drama' || 'ai_series' => 'AI剧',
    '' => '短剧',
    _ => category,
  };
}

int intValue(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

class Drama {
  const Drama({
    required this.id,
    required this.source,
    required this.title,
    this.sourceId = '',
    this.description = '',
    this.cover = '',
    this.episodes = 0,
    this.category = '',
    bool? vip,
    this.heat = '',
    this.views = '',
    this.onlineDate = '',
    this.tags = const [],
    this.releaseStatus = '',
  }) : vipStatus = vip;
  final String id;
  final String source;
  final String sourceId;
  final String title;
  final String description;
  final String cover;
  final int episodes;
  final String category;
  String get displayCategory => dramaCategoryLabel(category);
  final bool? vipStatus;
  bool get vip =>
      (source == 'hongguo' || id.startsWith('hongguo:'))
          ? false
          : vipStatus == true;
  final String heat;
  final String views;
  final String onlineDate;
  final List<String> tags;
  final String releaseStatus;
  String get releaseLabel => switch (releaseStatus) {
    'finished' || 'completed' => '已完结',
    'ongoing' => '连载中',
    'upcoming' => '待上线',
    _ => '状态未知',
  };
  String get cleanSourceId {
    final raw = sourceId.isNotEmpty ? sourceId : id;
    if (raw.contains(':')) {
      return raw.split(':').last;
    }
    if (source.isNotEmpty && raw.startsWith('${source}_')) {
      return raw.substring(source.length + 1);
    }
    return raw;
  }

  factory Drama.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String? ?? '';
    var id = json['id'] as String? ?? '';
    var source = json['source'] as String? ?? '';
    final hasSourceId = json.containsKey('sourceId');
    var sourceId = json['sourceId'] as String? ?? '';
    if (source.isEmpty && id.contains(':')) {
      final colonIndex = id.indexOf(':');
      source = id.substring(0, colonIndex);
      if (!hasSourceId) sourceId = id.substring(colonIndex + 1);
    }
    if (source.isEmpty) {
      source = JsSourceService.current?.activeSourceId ?? 'hongguo';
    }
    if (!hasSourceId || sourceId.isEmpty || sourceId.contains(':')) {
      if (sourceId.contains(':')) {
        sourceId = sourceId.split(':').last;
      } else if (id.contains(':')) {
        sourceId = id.split(':').last;
      } else if (sourceId.isEmpty) {
        sourceId = id;
      }
    }
    if (source.isNotEmpty && sourceId.startsWith('${source}_')) {
      sourceId = sourceId.substring(source.length + 1);
    }
    if (!id.contains(':') && source.isNotEmpty && id.isNotEmpty) {
      id = '$source:$id';
    }
    final isHongguo = source.isEmpty || source == 'hongguo' || id.startsWith('hongguo:');
    final tags = (json['tags'] as List? ?? const [])
        .whereType<String>()
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && !_isVipOrPaidTag(t))
        .toList();
    return Drama(
      id: id,
      source: source,
      sourceId: sourceId,
      title: json['title'] as String? ?? '短剧',
      description: json['description'] as String? ?? '',
      cover: normalizeCoverUrl(json['cover'] as String? ?? ''),
      episodes: intValue(json['episodes']),
      category: category.isEmpty ? '' : dramaCategoryLabel(category),
      vip: isHongguo ? false : (json['vip'] == true ? true : (json['vip'] == false ? false : null)),
      heat: json['heat']?.toString() ?? '',
      views: json['views']?.toString() ?? '',
      onlineDate: json['onlineDate'] as String? ?? '',
      tags: tags,
      releaseStatus: json['releaseStatus'] as String? ?? '',
    );
  }
  Map<String, dynamic> toJson() => {
    'metadataSchema': 1,
    'id': id,
    'source': source,
    'sourceId': sourceId,
    'title': title,
    'description': description,
    'cover': cover,
    'episodes': episodes,
    'category': category,
    'vip': vipStatus,
    'heat': heat,
    'views': views,
    'onlineDate': onlineDate,
    'tags': tags,
    'releaseStatus': releaseStatus,
  };

  Drama merge(Drama fresh) {
    if (id != fresh.id) return fresh;
    const genericCategories = {
      '短剧',
      '真人剧',
      '漫剧',
      'AI剧',
      'AI 剧',
      'AI短剧',
      'AI 短剧',
      'AI漫剧',
      'AI 漫剧',
    };
    return Drama(
      id: id,
      source: fresh.source.isEmpty ? source : fresh.source,
      sourceId: fresh.sourceId.isEmpty ? sourceId : fresh.sourceId,
      title: fresh.title.isEmpty || fresh.title == '短剧' ? title : fresh.title,
      description: fresh.description.isEmpty ? description : fresh.description,
      cover: fresh.cover.isEmpty ? cover : fresh.cover,
      episodes: fresh.episodes > 0 ? fresh.episodes : episodes,
      category:
          fresh.category.isEmpty ||
              genericCategories.contains(fresh.category) &&
                  category.isNotEmpty &&
                  !genericCategories.contains(category)
          ? category
          : fresh.category,
      vip: fresh.vipStatus ?? vipStatus,
      heat: fresh.heat.isEmpty ? heat : fresh.heat,
      views: fresh.views.isEmpty ? views : fresh.views,
      onlineDate: fresh.onlineDate.isEmpty ? onlineDate : fresh.onlineDate,
      tags: fresh.tags.isEmpty ? tags : fresh.tags,
      releaseStatus:
          fresh.releaseStatus.isEmpty || fresh.releaseStatus == 'unknown'
          ? releaseStatus
          : fresh.releaseStatus,
    );
  }
}

bool _isVipOrPaidTag(String tag) {
  final lower = tag.trim().toLowerCase();
  return lower == 'vip' ||
      lower == '付费' ||
      lower == '付费短剧' ||
      lower == 'vip专享' ||
      lower == '付费内容' ||
      lower == '付费解锁';
}

class Episode {
  Episode(this.raw, int fallback)
    : id = raw['id'] as String? ?? '',
      title = raw['title'] as String? ?? '第$fallback集',
      number = intValue(raw['currentEpisode']) > 0
          ? intValue(raw['currentEpisode'])
          : fallback,
      vip = (raw['source'] == 'hongguo' ||
              (raw['id'] as String? ?? '').startsWith('hongguo:') ||
              (raw['url'] as String? ?? '').contains('hongguoduanju.com'))
          ? false
          : raw['vip'] == true;
  final Map<String, dynamic> raw;
  final String id;
  final String title;
  final int number;
  final bool vip;
}

class DramaDetail {
  DramaDetail(this.drama, this.episodes, {this.warning = ''});
  final Drama drama;
  final List<Episode> episodes;
  final String warning;

  Map<String, dynamic> toJson() => {
    'drama': drama.toJson(),
    'chapters': [for (final ep in episodes) ep.raw],
    'warning': warning,
  };

  factory DramaDetail.fromJson(Map<String, dynamic> json) {
    final rows = json['chapters'] as List? ?? const [];
    return DramaDetail(
      Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
      [
        for (var i = 0; i < rows.length; i++)
          Episode(Map<String, dynamic>.from(rows[i] as Map), i + 1),
      ],
      warning: json['warning'] as String? ?? '',
    );
  }
}

class SeriesSeason {
  const SeriesSeason({
    required this.drama,
    required this.season,
    required this.playable,
    this.status = '',
  });

  final Drama drama;
  final int season;
  final bool playable;
  final String status;

  factory SeriesSeason.fromJson(Map<String, dynamic> json) => SeriesSeason(
    drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
    season: (json['season'] as num).toInt(),
    playable: json['playable'] == true,
    status: json['status'] as String? ?? '',
  );
}

class CatalogPage {
  CatalogPage(
    this.items, {
    this.hasMore = false,
    this.warning = '',
    this.page = 1,
    this.fresh = false,
  });
  final List<Drama> items;
  final bool hasMore;
  final String warning;
  final int page;
  final bool fresh;
  factory CatalogPage.fromJson(Map<String, dynamic> json) => CatalogPage(
    [
      for (final row in json['items'] as List? ?? const [])
        Drama.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    hasMore: json['hasMore'] == true,
    warning: json['warning'] as String? ?? '',
    page: intValue(json['page']) > 0 ? intValue(json['page']) : 1,
    fresh: json['fresh'] == true,
  );
}

class PlaybackPlan {
  const PlaybackPlan({
    required this.url,
    this.headers = const {},
    this.decryptionKey = '',
    this.mediaBytes = 0,
    this.quality = 0,
    this.qualities = const [],
    this.session = '',
    this.danmakuId = '',
    this.prefetchedBytes = 0,
    this.expiresAt = 0,
    this.routeIndex = 0,
    this.routeCount = 1,
    this.local = false,
    this.onlineCache = false,
  });
  final String url;
  final Map<String, String> headers;
  final String decryptionKey;
  final int mediaBytes;
  final int quality;
  final List<int> qualities;
  final String session;
  final String danmakuId;
  final int prefetchedBytes;
  final int expiresAt;
  final int routeIndex;
  final int routeCount;
  final bool local;
  final bool onlineCache;
  bool get offline => local && !onlineCache;
  bool get hasAlternative => session.isNotEmpty && routeIndex + 1 < routeCount;
  factory PlaybackPlan.fromJson(Map<String, dynamic> json) => PlaybackPlan(
    url: json['url'] as String? ?? '',
    local: json['local'] == true,
    onlineCache: json['onlineCache'] == true,
    headers: (json['headers'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    decryptionKey: json['decryptionKey'] as String? ?? '',
    mediaBytes: intValue(json['mediaBytes']),
    quality: intValue(json['quality']),
    qualities: (json['qualities'] as List? ?? []).map(intValue).toSet().toList()
      ..sort((a, b) => b.compareTo(a)),
    session: json['session'] as String? ?? '',
    danmakuId: json['danmakuId'] as String? ?? '',
    prefetchedBytes: intValue(json['prefetchedBytes']),
    expiresAt: intValue(json['expiresAt']),
    routeIndex: intValue(json['routeIndex']),
    routeCount: intValue(json['routeCount']) > 0
        ? intValue(json['routeCount'])
        : 1,
  );
}

class WatchEntry {
  WatchEntry({
    required this.drama,
    required this.episode,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });
  final Drama drama;
  final int episode;
  final double position;
  final double duration;
  final DateTime updatedAt;
  bool get finished => duration > 1 && position >= duration - 1;
  Map<String, dynamic> toJson() => {
    'drama': drama.toJson(),
    'episode': episode,
    'position': position,
    'duration': duration,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
  factory WatchEntry.fromJson(Map<String, dynamic> json) => WatchEntry(
    drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
    episode: intValue(json['episode']),
    position: (json['position'] as num?)?.toDouble() ?? 0,
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
    updatedAt:
        DateTime.tryParse(json['updatedAt'].toString())?.toLocal() ?? DateTime(2000),
  );
}

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.drama,
    required this.episode,
    required this.state,
    this.bytes = 0,
    this.total = 0,
    this.progress = 0,
    this.quality = 0,
    this.actualQuality = 0,
    this.error = '',
    this.created = 0,
    this.revision = 0,
    this.archived = false,
  });
  final int created;
  final int revision;
  final bool archived;
  final String id;
  final Drama drama;
  final Episode episode;
  final String state;
  final int bytes;
  final int total;
  final double progress;
  final int quality;
  final int actualQuality;
  final String error;
  bool get completed => state == 'completed';
  bool get active => state == 'queued' || state == 'downloading';
  bool get resumable => state == 'paused' || state == 'failed';
  String get stateLabel => switch (state) {
    'queued' => '等待下载',
    'downloading' => '正在下载',
    'paused' => '已暂停',
    'failed' => '下载失败',
    'completed' => '已下载',
    'removing' => '正在取消',
    _ => '等待更新',
  };
  factory DownloadJob.fromJson(Map<String, dynamic> value) => DownloadJob(
    id: value['id'] as String? ?? '',
    drama: Drama.fromJson(Map<String, dynamic>.from(value['drama'] as Map)),
    episode: Episode(
      Map<String, dynamic>.from(value['chapter'] as Map),
      intValue(value['index']),
    ),
    state: value['state'] as String? ?? 'failed',
    bytes: intValue(value['bytes']),
    total: intValue(value['total']),
    progress: ((value['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1),
    quality: intValue(value['quality']),
    actualQuality: intValue(value['actualQuality']),
    error: value['error'] as String? ?? '',
    created: intValue(value['created']),
    revision: intValue(value['revision']),
    archived: value['archived'] == true,
  );
}

List<Map<String, dynamic>> readJsonList(String? value) {
  try {
    return (jsonDecode(value ?? '[]') as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  } catch (_) {
    return [];
  }
}
