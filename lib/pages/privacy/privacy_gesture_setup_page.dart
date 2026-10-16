import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/privacy/pattern_lock_view.dart';

class PrivacyGestureSetupPage extends StatefulWidget {
  const PrivacyGestureSetupPage({
    super.key,
    required this.controller,
  });

  final PrivacyLockController controller;

  @override
  State<PrivacyGestureSetupPage> createState() =>
      _PrivacyGestureSetupPageState();
}

class _PrivacyGestureSetupPageState extends State<PrivacyGestureSetupPage> {
  int _step = 1;
  List<int>? _firstPattern;
  bool _isError = false;
  String _hintMessage = '绘制解锁图案（至少连接 4 个点）';
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _onPatternComplete(List<int> pattern) {
    if (_isError) return;

    if (pattern.length < 4) {
      _showError('至少连接 4 个点，请重新绘制');
      return;
    }

    if (_step == 1) {
      _firstPattern = List.unmodifiable(pattern);
      HapticFeedback.lightImpact();
      setState(() {
        _step = 2;
        _hintMessage = '再次绘制图案以确认';
      });
    } else {
      if (_patternsMatch(_firstPattern!, pattern)) {
        HapticFeedback.mediumImpact();
        widget.controller.saveGesture(pattern);
        Navigator.pop(context, true);
      } else {
        _showError('与上次图案不一致，请重新绘制');
        _step = 1;
        _firstPattern = null;
      }
    }
  }

  bool _patternsMatch(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _showError(String message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _isError = true;
      _hintMessage = message;
    });
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _isError = false;
          _hintMessage = _step == 1
              ? '绘制解锁图案（至少连接 4 个点）'
              : '再次绘制图案以确认';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('设置手势密码'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 1),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.accentSubtle12,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.gesture_rounded,
                color: AppColors.hongguoRed,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _step == 1 ? '创建手势密码' : '确认手势密码',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _hintMessage,
                key: ValueKey(_hintMessage),
                style: TextStyle(
                  fontSize: 14,
                  color: _isError
                      ? AppColors.error
                      : isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                  fontWeight: _isError ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            const Spacer(flex: 2),
            PatternLockView(
              key: ValueKey('step-$_step'),
              isError: _isError,
              dimension: 300,
              onComplete: _onPatternComplete,
            ),
            const Spacer(flex: 3),
            if (_step == 2)
              TextButton(
                onPressed: () {
                  setState(() {
                    _step = 1;
                    _firstPattern = null;
                    _hintMessage = '绘制解锁图案（至少连接 4 个点）';
                  });
                },
                child: const Text('重新绘制'),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
