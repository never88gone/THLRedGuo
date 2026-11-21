import 'package:flutter/material.dart';

import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/views/remote/remote_widgets.dart';

class TelevisionEpisodeDialog extends StatelessWidget {
  const TelevisionEpisodeDialog({
    super.key,
    required this.episodes,
    required this.currentIndex,
  });
  final List<Episode> episodes;
  final int currentIndex;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('选集 · 共 ${episodes.length} 集'),
    content: SizedBox(
      width: 700,
      height: MediaQuery.sizeOf(context).height * .55,
      child: LayoutBuilder(
        builder: (context, constraints) => RemoteGrid(
          itemKeys: episodes.map((episode) => '${episode.number}').toList(),
          columns: ((constraints.maxWidth - 12) / 96).floor().clamp(1, 8),
          itemExtent: 64,
          initialIndex: currentIndex,
          autofocus: true,
          padding: const EdgeInsets.all(6),
          itemBuilder: (_, index, node, onFocus) => RemoteEpisodeButton(
            key: ValueKey('tv-select-episode-${episodes[index].number}'),
            number: episodes[index].number,
            vip: episodes[index].vip,
            current: index == currentIndex,
            focusNode: node,
            onFocus: onFocus,
            onPressed: () => Navigator.pop(context, index),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('返回播放'),
      ),
    ],
  );
}
