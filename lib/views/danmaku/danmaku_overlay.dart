import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/core/danmaku/danmaku_controller.dart';
import 'package:THLRedLook/models/danmaku/danmaku_models.dart';

class DanmakuFlight {
  const DanmakuFlight(
    this.item,
    this.text,
    this.lane,
    this.width,
    this.durationMs,
  );
  final DanmakuItem item;
  final String text;
  final int lane;
  final double width;
  final int durationMs;
}

int calculateDanmakuLifetimeMs(DanmakuItem item) {
  final hash = item.id.hashCode.abs();
  final factor = (hash % 1000) / 1000.0;
  final offset = ((factor - 0.5) * 3000).round();
  return (8000 + offset).clamp(6500, 9800);
}

List<DanmakuFlight> planDanmaku(
  List<DanmakuItem> items, {
  required double width,
  required int rows,
  required double Function(String) measure,
}) {
  if (!width.isFinite || width <= 0 || rows < 1) return const [];
  final laneCount = rows.clamp(1, 8);
  final lanes = List<DanmakuFlight?>.filled(laneCount, null);
  final sorted = items.toList()..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final seen = <String>{};
  final flights = <DanmakuFlight>[];

  for (final item in sorted) {
    if (item.id.isEmpty ||
        item.text.trim().isEmpty ||
        item.timeMs < 0 ||
        !seen.add(item.id)) {
      continue;
    }
    if (flights.reversed
            .takeWhile(
              (flight) => item.timeMs - flight.item.timeMs < flight.durationMs,
            )
            .length >=
        40) {
      continue;
    }
    final runes = item.text.runes;
    final text =
        String.fromCharCodes(runes.take(100)) + (runes.length > 100 ? '…' : '');
    final size = measure(text).ceilToDouble() + 8;
    final durationMs = calculateDanmakuLifetimeMs(item);

    int bestLane = -1;
    double maxSafetyMargin = -1;

    for (int l = 0; l < laneCount; l++) {
      final prev = lanes[l];
      if (prev == null) {
        bestLane = l;
        break;
      }
      final gap = item.timeMs - prev.item.timeMs;
      if (gap >= prev.durationMs) {
        bestLane = l;
        break;
      }

      // 条件 1: 入场碰撞检查（后弹幕入场时，前弹幕尾部已完全进入且拉开至少 28px）
      final prevSpeed = (width + prev.width) / prev.durationMs;
      final prevMovedAtEntry = prevSpeed * gap;
      final entryClearance = prevMovedAtEntry - prev.width;
      if (entryClearance < 28) {
        continue;
      }

      // 条件 2: 出场追尾检查（在前弹幕出屏幕前，后弹幕不能追上前弹幕尾部）
      final currSpeed = (width + size) / durationMs;
      final remainingTime = prev.durationMs - gap;
      final currMovedAtPrevExit = currSpeed * remainingTime;
      final exitClearance = width - currMovedAtPrevExit;
      if (exitClearance < 28) {
        continue;
      }

      final safetyMargin = math.min(entryClearance, exitClearance);
      if (safetyMargin > maxSafetyMargin) {
        maxSafetyMargin = safetyMargin;
        bestLane = l;
      }
    }

    if (bestLane < 0) continue;

    final flight = DanmakuFlight(item, text, bestLane, size, durationMs);
    lanes[bestLane] = flight;
    flights.add(flight);
  }
  return flights;
}

class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    required this.aspectRatio,
    this.style = const DanmakuStyle(),
  });
  final DanmakuController controller;
  final double aspectRatio;
  final DanmakuStyle style;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  Object? _layout;
  List<DanmakuFlight> _schedule = const [];

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final aspect = widget.aspectRatio.isFinite && widget.aspectRatio > 0
              ? widget.aspectRatio
              : 16 / 9;
          final width = math.min(
            constraints.maxWidth,
            constraints.maxHeight * aspect,
          );
          final height = math.min(
            constraints.maxHeight,
            constraints.maxWidth / aspect,
          );
          final baseFontSize = width < 600 ? 16.0 : 20.0;
          final fontSize = baseFontSize * widget.style.fontSizeScale;
          final scaler = MediaQuery.textScalerOf(context);
          final rowHeight = scaler.scale(fontSize) * 1.5;
          final rows = ((height * widget.style.displayArea - 8) / rowHeight).floor().clamp(0, 10);
          final opacity = widget.style.opacity.clamp(0.1, 1.0);
          final style = TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: AppColors.white.withValues(alpha: opacity),
            height: 1.2,
            shadows: [
              Shadow(
                color: AppColors.black.withValues(alpha: opacity * 0.85),
                blurRadius: 3,
                offset: const Offset(1, 1),
              ),
            ],
          );
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final controller = widget.controller;
                    if (!controller.visible || rows == 0) {
                      return const SizedBox.shrink();
                    }
                    final layout = (
                      controller,
                      controller.dataRevision,
                      width,
                      rows,
                      fontSize,
                      scaler,
                      widget.style.fontSizeScale,
                      widget.style.opacity,
                      widget.style.displayArea,
                    );
                    if (_layout != layout) {
                      _layout = layout;
                      _schedule = planDanmaku(
                        controller.items,
                        width: width,
                        rows: rows,
                        measure: (text) {
                          final painter = TextPainter(
                            text: TextSpan(text: text, style: style),
                            textDirection: TextDirection.ltr,
                            textScaler: scaler,
                            maxLines: 1,
                          )..layout();
                          final measured = painter.width;
                          painter.dispose();
                          return measured;
                        },
                      );
                    }
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final flight in _schedule)
                          if (controller.positionMs >= flight.item.timeMs &&
                              controller.positionMs <
                                  flight.item.timeMs + flight.durationMs)
                            Positioned(
                              key: ValueKey('danmaku-item-${flight.item.id}'),
                              left: 0,
                              top: 8 + flight.lane * rowHeight,
                              width: flight.width,
                              height: rowHeight,
                              child: _DanmakuMotion(
                                flight: flight,
                                width: width,
                                positionMs: controller.positionMs,
                                moving: controller.moving,
                                rate: controller.rate,
                                revision: controller.motionRevision,
                                style: style,
                                scaler: scaler,
                              ),
                            ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _DanmakuMotion extends StatefulWidget {
  const _DanmakuMotion({
    required this.flight,
    required this.width,
    required this.positionMs,
    required this.moving,
    required this.rate,
    required this.revision,
    required this.style,
    required this.scaler,
  });
  final DanmakuFlight flight;
  final double width;
  final int positionMs;
  final bool moving;
  final double rate;
  final int revision;
  final TextStyle style;
  final TextScaler scaler;

  @override
  State<_DanmakuMotion> createState() => _DanmakuMotionState();
}

class _DanmakuMotionState extends State<_DanmakuMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_DanmakuMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.positionMs != widget.positionMs ||
        oldWidget.width != widget.width ||
        oldWidget.flight.width != widget.flight.width ||
        oldWidget.flight.item.timeMs != widget.flight.item.timeMs ||
        oldWidget.flight.durationMs != widget.flight.durationMs) {
      _sync();
    }
  }

  void _sync() {
    _motion.stop();
    final lifetime = widget.flight.durationMs;
    final elapsed = (widget.positionMs - widget.flight.item.timeMs).clamp(
      0,
      lifetime,
    );
    _motion.value = elapsed / lifetime;
    if (widget.moving && elapsed < lifetime) {
      _motion.animateTo(
        (elapsed + 750).clamp(0, lifetime) / lifetime,
        duration: Duration(
          microseconds:
              ((lifetime - elapsed).clamp(1, 750) * 1000 / widget.rate)
                  .round()
                  .clamp(1, 86400000000),
        ),
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: RepaintBoundary(
      child: Text(
        widget.flight.text,
        style: widget.style,
        textScaler: widget.scaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        softWrap: false,
      ),
    ),
    builder: (context, child) => Transform.translate(
      key: ValueKey('danmaku-motion-${widget.flight.item.id}'),
      offset: Offset(
        widget.width - (widget.width + widget.flight.width) * _motion.value,
        0,
      ),
      child: child,
    ),
  );
}
