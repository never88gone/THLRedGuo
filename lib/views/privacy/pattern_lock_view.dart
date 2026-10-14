import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pattern_dot_painter.dart';

class PatternLockView extends StatefulWidget {
  const PatternLockView({
    super.key,
    required this.onComplete,
    this.isError = false,
    this.dimension = 280.0,
  });

  final ValueChanged<List<int>> onComplete;
  final bool isError;
  final double dimension;

  @override
  State<PatternLockView> createState() => _PatternLockViewState();
}

class _PatternLockViewState extends State<PatternLockView> {
  final List<int> _selectedDots = [];
  Offset? _currentTouchPoint;

  static const Map<String, int> _intermediateDots = {
    '0-2': 1, '2-0': 1,
    '3-5': 4, '5-3': 4,
    '6-8': 7, '8-6': 7,
    '0-6': 3, '6-0': 3,
    '1-7': 4, '7-1': 4,
    '2-8': 5, '8-2': 5,
    '0-8': 4, '8-0': 4,
    '2-6': 4, '6-2': 4,
  };

  Map<int, Offset> _calculateDotCenters(Size size) {
    final centers = <int, Offset>{};
    final cellWidth = size.width / 3;
    final cellHeight = size.height / 3;

    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final index = row * 3 + col;
        centers[index] = Offset(
          cellWidth * col + cellWidth / 2,
          cellHeight * row + cellHeight / 2,
        );
      }
    }
    return centers;
  }

  int? _findHitDot(Offset point, Map<int, Offset> centers, double hitRadius) {
    for (final entry in centers.entries) {
      final distance = (entry.value - point).distance;
      if (distance <= hitRadius) {
        return entry.key;
      }
    }
    return null;
  }

  void _addDot(int dotIndex) {
    if (_selectedDots.contains(dotIndex)) return;

    if (_selectedDots.isNotEmpty) {
      final lastDot = _selectedDots.last;
      final key = '$lastDot-$dotIndex';
      final intermediate = _intermediateDots[key];
      if (intermediate != null && !_selectedDots.contains(intermediate)) {
        _selectedDots.add(intermediate);
      }
    }

    _selectedDots.add(dotIndex);
    HapticFeedback.lightImpact();
  }

  void _handlePanStart(DragStartDetails details, Map<int, Offset> centers) {
    if (widget.isError) return;
    _selectedDots.clear();
    final hit = _findHitDot(details.localPosition, centers, 36.0);
    if (hit != null) {
      _addDot(hit);
    }
    _currentTouchPoint = details.localPosition;
    setState(() {});
  }

  void _handlePanUpdate(DragUpdateDetails details, Map<int, Offset> centers) {
    if (widget.isError) return;
    final hit = _findHitDot(details.localPosition, centers, 36.0);
    if (hit != null) {
      _addDot(hit);
    }
    _currentTouchPoint = details.localPosition;
    setState(() {});
  }

  void _handlePanEnd(DragEndDetails details) {
    if (widget.isError) return;
    _currentTouchPoint = null;
    setState(() {});
    if (_selectedDots.isNotEmpty) {
      widget.onComplete(List.unmodifiable(_selectedDots));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.dimension, widget.dimension);
    final centers = _calculateDotCenters(size);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: GestureDetector(
        onPanStart: (details) => _handlePanStart(details, centers),
        onPanUpdate: (details) => _handlePanUpdate(details, centers),
        onPanEnd: _handlePanEnd,
        child: CustomPaint(
          size: size,
          painter: PatternDotPainter(
            selectedDots: _selectedDots,
            dotCenters: centers,
            currentTouchPoint: _currentTouchPoint,
            isError: widget.isError,
            isDark: isDark,
          ),
        ),
      ),
    );
  }
}
