import 'package:THLRedLook/models/catalog/models.dart';

class FeedItem {
  const FeedItem({required this.drama, this.episode = 1, this.position = 0});
  final Drama drama;
  final int episode;
  final double position;

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
    drama: Drama.fromJson(Map<String, dynamic>.from(json['drama'] as Map)),
    episode: (json['episode'] as num?)?.toInt() ?? 1,
    position: (json['position'] as num?)?.toDouble() ?? 0,
  );
}

class FeedPage {
  const FeedPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });
  final List<FeedItem> items;
  final int page;
  final bool hasMore;

  factory FeedPage.fromJson(Map<String, dynamic> json) => FeedPage(
    items: (json['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => FeedItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    page: (json['page'] as num?)?.toInt() ?? 1,
    hasMore: json['hasMore'] == true,
  );
}
