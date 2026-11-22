import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 具备遥控器焦点高亮感知与电视端无缝交互的通用设置项
class SettingsTile extends StatefulWidget {
  const SettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.selected = false,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool selected;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultTrailing = const Icon(
      Icons.chevron_right_rounded,
      size: 20,
    );

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.onTap != null,
      onFocusChange: _handleFocusChange,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: widget.onTap != null,
        focused: _focused,
        child: MouseRegion(
          cursor: widget.onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              padding: widget.contentPadding,
              decoration: BoxDecoration(
                color: _focused
                    ? (isDark ? AppColors.darkSurfaceHighest : AppColors.accentSubtle12)
                    : widget.selected
                        ? (isDark ? AppColors.darkSurfaceHigh : AppColors.greyLight)
                        : AppColors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _focused
                      ? AppColors.hongguoRed
                      : widget.selected
                          ? AppColors.hongguoRedLight
                          : AppColors.transparent,
                  width: _focused ? 2.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  if (widget.leading != null) ...[
                    IconTheme(
                      data: IconThemeData(
                        color: _focused
                            ? AppColors.hongguoRed
                            : (widget.selected
                                ? AppColors.hongguoRed
                                : theme.iconTheme.color),
                        size: 24,
                      ),
                      child: widget.leading!,
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle(
                          style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: _focused || widget.selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: _focused
                                    ? AppColors.hongguoRed
                                    : null,
                              ) ??
                              const TextStyle(),
                          child: widget.title,
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 3),
                          DefaultTextStyle(
                            style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withValues(alpha: 0.8),
                                ) ??
                                const TextStyle(),
                            child: widget.subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconTheme(
                    data: IconThemeData(
                      color: _focused
                          ? AppColors.hongguoRed
                          : theme.disabledColor,
                    ),
                    child: widget.trailing ?? defaultTrailing,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
