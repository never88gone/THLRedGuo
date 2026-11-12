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
