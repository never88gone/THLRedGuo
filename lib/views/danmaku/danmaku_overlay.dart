import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/utils/emoji/emoji_helper.dart';
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

String _formatDanmakuText(String raw) {
  final emojified = EmojiHelper.emojify(raw);
  final runes = emojified.runes;
  return String.fromCharCodes(runes.take(100)) + (runes.length > 100 ? '…' : '');
}

List<DanmakuFlight> planDanmaku(
  List<DanmakuItem> items, {
  required double width,
  required int rows,
  required double Function(String) measure,
  double speed = 1.0,
}) {
  if (!width.isFinite || width <= 0 || rows < 1) return const [];
  final effectiveSpeed = speed.isFinite && speed > 0 ? speed : 1.0;
  final laneCount = rows.clamp(1, 8);
  final lanes = List<DanmakuFlight?>.filled(laneCount, null);
  final sorted = items.toList()..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final seen = <String>{};
  final flights = <DanmakuFlight>[];

  final maxConcurrent = width > 800 ? 18 : 30;
  for (final item in sorted) {
    if (item.id.isEmpty ||
        item.text.trim().isEmpty ||
        item.timeMs < 0 ||
        !seen.add(item.id)) {
      continue;
    }
    if (flights.reversed
            .takeWhile(
              (flight) =>
                  ((item.timeMs - flight.item.timeMs) / effectiveSpeed) <
                  flight.durationMs,
            )
            .length >=
        maxConcurrent) {
      continue;
    }
    final text = _formatDanmakuText(item.text);
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
      final gap = ((item.timeMs - prev.item.timeMs) / effectiveSpeed).round();
      if (gap >= prev.durationMs) {
        bestLane = l;
        break;
      }
      final margin = _laneSafetyMargin(
        width: width,
        prevWidth: prev.width,
        prevDurationMs: prev.durationMs,
        currWidth: size,
        currDurationMs: durationMs,
        gapMs: gap,
      );
      if (margin != null && margin > maxSafetyMargin) {
        maxSafetyMargin = margin;
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

double? _laneSafetyMargin({
  required double width,
  required double prevWidth,
  required int prevDurationMs,
  required double currWidth,
  required int currDurationMs,
  required int gapMs,
}) {
  if (gapMs <= 0) return null;
  // 条件 1: 入场碰撞检查（后弹幕入场时，前弹幕尾部已完全进入且拉开至少 28px）
  final prevSpeed = (width + prevWidth) / prevDurationMs;
  final prevMovedAtEntry = prevSpeed * gapMs;
  final entryClearance = prevMovedAtEntry - prevWidth;
  if (entryClearance < 28) {
    return null;
  }

  // 条件 2: 出场追尾检查（在前弹幕出屏幕前，后弹幕不能追上前弹幕尾部）
  final currSpeed = (width + currWidth) / currDurationMs;
  final remainingTime = prevDurationMs - gapMs;
  final currMovedAtPrevExit = currSpeed * remainingTime;
  final exitClearance = width - currMovedAtPrevExit;
  if (exitClearance < 28) {
    return null;
  }

  return math.min(entryClearance, exitClearance);
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

class _ActiveFlight {
  const _ActiveFlight({required this.flight, required this.spawnScreenMs});

  final DanmakuFlight flight;
  final int spawnScreenMs;
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  DanmakuController? _controller;
  int _timelineRevision = -1;
  int _lastPositionMs = -1;
  double _lastWidth = -1;
  int _lastRows = -1;
  double _lastFontSize = -1;
  TextScaler? _lastScaler;
  final Map<String, _ActiveFlight> _active = {};
  final Set<String> _retiredIds = {};

  void _resetSchedule() {
    _active.clear();
    _retiredIds.clear();
  }

  double _measureText(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final measured = painter.width;
    painter.dispose();
    return measured;
  }

  void _syncActiveFlights({
    required DanmakuController controller,
    required double width,
    required int rows,
    required double fontSize,
    required TextStyle style,
    required TextScaler scaler,
  }) {
    if (!identical(_controller, controller) ||
        _timelineRevision != controller.timelineRevision ||
        controller.positionMs < _lastPositionMs ||
        _lastWidth != width ||
        _lastRows != rows ||
        _lastFontSize != fontSize ||
        _lastScaler != scaler) {
      _controller = controller;
      _timelineRevision = controller.timelineRevision;
      _lastWidth = width;
      _lastRows = rows;
      _lastFontSize = fontSize;
      _lastScaler = scaler;
      _resetSchedule();
    }
    _lastPositionMs = controller.positionMs;

    final screenMs = controller.effectiveScreenMs;
    _active.removeWhere((id, entry) {
      if (screenMs >= entry.spawnScreenMs + entry.flight.durationMs) {
        _retiredIds.add(id);
        return true;
      }
      return false;
    });

    final validIds = controller.items.map((item) => item.id).toSet();
    _retiredIds.removeWhere((id) => !validIds.contains(id));

    final speed = controller.rate.isFinite && controller.rate > 0
        ? controller.rate
        : 1.0;
    final laneCount = rows.clamp(1, 8);
    final maxConcurrent = width > 800 ? 18 : 30;

    for (final item in controller.items) {
      if (item.id.isEmpty ||
          item.text.trim().isEmpty ||
          item.timeMs < 0 ||
          item.timeMs > controller.positionMs ||
          _active.containsKey(item.id) ||
          _retiredIds.contains(item.id)) {
        continue;
      }

      final elapsedOffsetMs = ((controller.positionMs - item.timeMs) / speed)
          .round();
      final durationMs = calculateDanmakuLifetimeMs(item);
      if (elapsedOffsetMs >= durationMs || _active.length >= maxConcurrent) {
        _retiredIds.add(item.id);
        continue;
      }

      final text = _formatDanmakuText(item.text);
      final size = _measureText(text, style, scaler).ceilToDouble() + 8;
      final spawnScreenMs = screenMs - elapsedOffsetMs;

      final laneLatest = List<_ActiveFlight?>.filled(laneCount, null);
      for (final active in _active.values) {
        final lane = active.flight.lane;
        if (lane < 0 || lane >= laneCount) continue;
        final current = laneLatest[lane];
        if (current == null || active.spawnScreenMs > current.spawnScreenMs) {
          laneLatest[lane] = active;
        }
      }

      int bestLane = -1;
      double maxSafetyMargin = -1;
      for (int l = 0; l < laneCount; l++) {
        final prev = laneLatest[l];
        if (prev == null) {
          bestLane = l;
          break;
        }
        final gapMs = spawnScreenMs - prev.spawnScreenMs;
        if (gapMs >= prev.flight.durationMs) {
          bestLane = l;
          break;
        }
        final margin = _laneSafetyMargin(
          width: width,
          prevWidth: prev.flight.width,
          prevDurationMs: prev.flight.durationMs,
          currWidth: size,
          currDurationMs: durationMs,
          gapMs: gapMs,
        );
        if (margin != null && margin > maxSafetyMargin) {
          maxSafetyMargin = margin;
          bestLane = l;
        }
      }

      if (bestLane < 0) {
        _retiredIds.add(item.id);
        continue;
      }

      _active[item.id] = _ActiveFlight(
        flight: DanmakuFlight(item, text, bestLane, size, durationMs),
        spawnScreenMs: spawnScreenMs,
      );
    }
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            _resetSchedule();
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
          final maxRows = width > 800 ? 5 : 8;
          final rows = ((height * widget.style.displayArea - 8) / rowHeight)
              .floor()
              .clamp(0, maxRows);
          final opacity = widget.style.opacity.clamp(0.1, 1.0);
          final style = EmojiHelper.withEmojiFont(
            TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: AppColors.white.withValues(alpha: opacity),
              height: 1.2,
              shadows: [
                Shadow(
                  color: AppColors.black.withValues(alpha: opacity * 0.85),
                  blurRadius: width > 800 ? 0 : 2,
                  offset: const Offset(1, 1),
                ),
              ],
            ),
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
                      _resetSchedule();
                      return const SizedBox.shrink();
                    }
                    _syncActiveFlights(
                      controller: controller,
                      width: width,
                      rows: rows,
                      fontSize: fontSize,
                      style: style,
                      scaler: scaler,
                    );
                    final screenMs = controller.effectiveScreenMs;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final active in _active.values)
                          Positioned(
                            key: ValueKey('danmaku-item-${active.flight.item.id}'),
                            left: 0,
                            top: 8 + active.flight.lane * rowHeight,
                            width: active.flight.width,
                            height: rowHeight,
                            child: _DanmakuMotion(
                              flight: active.flight,
                              width: width,
                              screenMs: screenMs,
                              spawnScreenMs: active.spawnScreenMs,
                              moving: controller.moving,
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
    required this.screenMs,
    required this.spawnScreenMs,
    required this.moving,
    required this.revision,
    required this.style,
    required this.scaler,
  });
  final DanmakuFlight flight;
  final double width;
  final int screenMs;
  final int spawnScreenMs;
  final bool moving;
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
    // Position updates admit new comments without restarting active motion.
    if (oldWidget.revision != widget.revision ||
        oldWidget.spawnScreenMs != widget.spawnScreenMs ||
        oldWidget.moving != widget.moving ||
        oldWidget.width != widget.width ||
        oldWidget.flight.width != widget.flight.width ||
        oldWidget.flight.item.timeMs != widget.flight.item.timeMs ||
        oldWidget.flight.durationMs != widget.flight.durationMs) {
      _sync();
    }
    if (oldWidget.style != widget.style || oldWidget.scaler != widget.scaler) {
      setState(() {});
    }
  }

  void _sync() {
    _motion.stop();
    final lifetime = widget.flight.durationMs;
    final elapsed = (widget.screenMs - widget.spawnScreenMs).clamp(
      0,
      lifetime,
    );
    _motion.value = elapsed / lifetime;
    if (widget.moving && elapsed < lifetime) {
      _motion.animateTo(
        1,
        duration: Duration(milliseconds: lifetime - elapsed),
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
