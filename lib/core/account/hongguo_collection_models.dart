import '../../models/catalog/models.dart';

class HongguoCollectionPage<T> {
  const HongguoCollectionPage(
    this.items, {
    required this.hasMore,
    this.nextOffset,
    this.followingDouyinOffset = 0,
    this.unsupportedCount = 0,
  });
  final List<T> items;
  final bool hasMore;
  final int? nextOffset;
  final int followingDouyinOffset, unsupportedCount;
}

class HongguoLikedVideo {
  const HongguoLikedVideo({
    required this.id,
    required this.title,
    required this.seriesId,
    this.cover = '',
    this.description = '',
    this.episode,
    this.episodes = 0,
    this.kind = 'episode',
  });
  final String id, title, seriesId, cover, description, kind;
  final int? episode;
  final int episodes;
  String get key => '$kind:$id';
  String get subtitle => kind == 'series'
      ? '已点赞合集'
      : episode != null
      ? '已点赞 · 第 $episode 集'
      : '已点赞视频';
  Drama? get drama => RegExp(r'^[1-9]\d{0,29}$').hasMatch(seriesId)
      ? Drama(
          id: 'hongguo:$seriesId',
          source: 'hongguo',
          sourceId: seriesId,
          title: title,
          cover: cover,
          description: description,
          episodes: episodes,
        )
      : null;
  factory HongguoLikedVideo.fromJson(Map<String, dynamic> row) =>
      HongguoLikedVideo(
        id: row['id'] as String,
        title: row['title'] as String? ?? '',
        seriesId: row['seriesId'] as String? ?? '',
        cover: row['cover'] as String? ?? '',
        description: row['description'] as String? ?? '',
        episode: (row['episode'] as num?)?.toInt(),
        episodes: (row['episodes'] as num?)?.toInt() ?? 0,
        kind: row['kind'] as String? ?? 'episode',
      );
}

class HongguoSubscribeItem {
  const HongguoSubscribeItem({
    required this.id,
    required this.title,
    this.cover = '',
    this.description = '',
    this.episodes = 0,
    this.category = '短剧',
    this.tags = const [],
    this.heat = '',
    this.onlineDate = '',
    this.releaseStatus = '',
    this.isOnline = false,
    this.subscribed = true,
    this.schedulePublishTime = 0,
  });

  final String id;
  final String title;
  final String cover;
  final String description;
  final int episodes;
  final String category;
  final List<String> tags;
  final String heat;
  final String onlineDate;
  final String releaseStatus;
  final bool isOnline;
  final bool subscribed;
  final int schedulePublishTime;

  String get subtitle {
    if (isOnline && episodes > 0) return '已上线 · 全 $episodes 集';
    if (onlineDate.isNotEmpty) return onlineDate;
    if (heat.isNotEmpty) return heat;
    return isOnline ? '已上线' : '待上线';
  }

  Drama get drama => Drama(
    id: 'hongguo:$id',
    source: 'hongguo',
    sourceId: id,
    title: title,
    cover: cover,
    description: description,
    episodes: episodes,
    category: category,
    tags: tags,
    heat: heat,
    onlineDate: onlineDate,
    releaseStatus: isOnline ? '' : (releaseStatus.isEmpty ? 'upcoming' : releaseStatus),
  );

  factory HongguoSubscribeItem.fromJson(Map<String, dynamic> row) =>
      HongguoSubscribeItem(
        id: row['id']?.toString() ?? '',
        title: row['title']?.toString() ?? '',
        cover: row['cover']?.toString() ?? '',
        description: row['description']?.toString() ?? '',
        episodes: (row['episodes'] as num?)?.toInt() ?? 0,
        category: row['category']?.toString() ?? '短剧',
        tags: (row['tags'] as List? ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        heat: row['heat']?.toString() ?? '',
        onlineDate: row['onlineDate']?.toString() ?? '',
        releaseStatus: row['releaseStatus']?.toString() ?? '',
        isOnline: row['isOnline'] == true,
        subscribed: row['subscribed'] != false,
        schedulePublishTime: (row['schedulePublishTime'] as num?)?.toInt() ?? 0,
      );
}
