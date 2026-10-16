import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:THLRedLook/utils/privacy/privacy_lock_controller.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/privacy/pattern_lock_view.dart';

class PrivacyLockPage extends StatefulWidget {
  const PrivacyLockPage({
    super.key,
    required this.controller,
  });

  final PrivacyLockController controller;

  @override
  State<PrivacyLockPage> createState() => _PrivacyLockPageState();
}

class _PrivacyLockPageState extends State<PrivacyLockPage> {
  bool _isError = false;
  String _hintMessage = '请绘制手势图案解锁';
  int _failedAttempts = 0;
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

    final success = widget.controller.verifyGesture(pattern);
    if (success) {
      HapticFeedback.mediumImpact();
    } else {
      _failedAttempts++;
      _showError('手势密码错误，已失败 $_failedAttempts 次');
    }
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
          _hintMessage = '请绘制手势图案解锁';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: AppColors.accentSubtle12,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.hongguoRed,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '真果·鉴 隐私保护',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
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
              const Spacer(flex: 3),
              PatternLockView(
                isError: _isError,
                dimension: 300,
                onComplete: _onPatternComplete,
              ),
              const Spacer(flex: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  '应用处于后台或切出时自动守护',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
