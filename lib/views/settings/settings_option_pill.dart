import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 具备遥控器焦点支持的横向分段选项胶囊按钮
class SettingsOptionPill extends StatefulWidget {
  const SettingsOptionPill({
    super.key,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<SettingsOptionPill> createState() => _SettingsOptionPillState();
}

class _SettingsOptionPillState extends State<SettingsOptionPill> {
  bool _focused = false;

  void _handleFocusChange(bool focused) {
    if (mounted) {
      setState(() => _focused = focused);
    }
    if (focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focused) {
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: _handleFocusChange,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        selected: widget.selected,
        focused: _focused,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.selected
                    ? AppColors.hongguoRed
                    : _focused
                        ? (widget.isDark
                            ? AppColors.darkSurfaceHighest
                            : AppColors.accentSubtle12)
                        : (widget.isDark
                            ? AppColors.darkSurface
                            : AppColors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _focused
                      ? AppColors.hongguoRed
                      : widget.selected
                          ? AppColors.hongguoRed
                          : (widget.isDark
                              ? AppColors.white15
                              : AppColors.black12),
                  width: _focused ? 2.5 : 1.0,
                ),
                boxShadow: widget.selected || _focused
                    ? [
                        BoxShadow(
                          color: AppColors.hongguoRed.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: widget.selected || _focused
                      ? FontWeight.bold
                      : FontWeight.w500,
                  color: widget.selected
                      ? AppColors.white
                      : _focused
                          ? AppColors.hongguoRed
                          : (widget.isDark
                              ? AppColors.whiteWithAlpha(0.85)
                              : AppColors.blackWithAlpha(0.85)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
