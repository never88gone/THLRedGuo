import 'package:THLRedLook/core/js/js_source_service.dart';
import 'package:THLRedLook/utils/media/cover_decoder.dart';

String dramaCategoryLabel(String value) {
  final category = value.trim();
  if (category.startsWith('app:discover:')) {
    return switch (category.split(':').last) {
      'playlet' => '真人剧',
      'motion_comic' => '漫剧',
      'ai_playlet' => 'AI剧',
      'subscribe' => '新剧预约',
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

bool isVipOrPaidTag(String tag) {
  final lower = tag.trim().toLowerCase();
  return lower == 'vip' ||
      lower == '付费' ||
      lower == '付费短剧' ||
      lower == 'vip专享' ||
      lower == '付费内容' ||
      lower == '付费解锁';
}

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
  bool get vip => (source == 'hongguo' || id.startsWith('hongguo:'))
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
    final isHongguo =
        source.isEmpty || source == 'hongguo' || id.startsWith('hongguo:');
    final tags = (json['tags'] as List? ?? const [])
        .whereType<String>()
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && !isVipOrPaidTag(t))
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
      vip: isHongguo
          ? false
          : (json['vip'] == true
                ? true
                : (json['vip'] == false ? false : null)),
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
      title: _isPlaceholderTitle(fresh.title) && !_isPlaceholderTitle(title)
          ? title
          : fresh.title,
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

  static bool _isPlaceholderTitle(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ||
        trimmed == '短剧' ||
        RegExp(r'^剧集\s*\d+$').hasMatch(trimmed);
  }
}
