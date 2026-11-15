import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MouseHorizontalScroll extends StatelessWidget {
  const MouseHorizontalScroll({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final delta = event.scrollDelta.dy != 0
            ? event.scrollDelta.dy
            : event.scrollDelta.dx;
        if (delta == 0) return;
        final c = controller ?? PrimaryScrollController.maybeOf(context);
        if (c == null || !c.hasClients) return;
        final position = c.position;
        final target =
            (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
        if (target != position.pixels) {
          c.jumpTo(target);
        }
      },
      child: child,
    );
  }
}
