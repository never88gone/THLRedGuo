import 'package:flutter/material.dart';

/// 剧集切换平滑垂直推移过渡容器
/// 在上下滑动切集时，提供类似短视频流的平滑位移过渡动效，消除生硬黑屏感
class EpisodeTransitionView extends StatefulWidget {
  const EpisodeTransitionView({
    super.key,
    required this.episodeIndex,
    required this.child,
  });

  final int episodeIndex;
  final Widget child;

  @override
  State<EpisodeTransitionView> createState() => _EpisodeTransitionViewState();
}

class _EpisodeTransitionViewState extends State<EpisodeTransitionView> {
  int _lastIndex = 0;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.episodeIndex;
  }

  @override
  void didUpdateWidget(covariant EpisodeTransitionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.episodeIndex != oldWidget.episodeIndex) {
      setState(() {
        _forward = widget.episodeIndex >= oldWidget.episodeIndex;
        _lastIndex = widget.episodeIndex;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == ValueKey('episode-$_lastIndex');
        final inOffset = _forward ? const Offset(0.0, 1.0) : const Offset(0.0, -1.0);
        final outOffset = _forward ? const Offset(0.0, -1.0) : const Offset(0.0, 1.0);

        final offsetTween = isIncoming
            ? Tween<Offset>(begin: inOffset, end: Offset.zero)
            : Tween<Offset>(begin: Offset.zero, end: outOffset);

        return SlideTransition(
          position: offsetTween.animate(animation),
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey('episode-$_lastIndex'),
        child: widget.child,
      ),
    );
  }
}
