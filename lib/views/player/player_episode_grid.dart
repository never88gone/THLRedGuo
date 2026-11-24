import 'package:flutter/material.dart';

import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/browser/episode_browser.dart';

/// 播放器选集网格组件
class PlayerEpisodeGrid extends StatelessWidget {
  const PlayerEpisodeGrid({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onSelected,
    this.keyPrefix = 'play-episode',
    this.compact = false,
    this.title = '选集',
  });

  final List<Episode> episodes;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  final bool compact;
  final String title;

  @override
  Widget build(BuildContext context) => EpisodeBrowser(
    episodes: episodes,
    currentNumber: episodes.isEmpty
        ? null
        : episodes[currentIndex.clamp(0, episodes.length - 1)].number,
    onSelected: onSelected,
    keyPrefix: keyPrefix,
    compact: compact,
    title: title,
  );
}
