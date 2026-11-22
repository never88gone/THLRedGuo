import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 具备遥控器焦点感知与高亮对比度的单选卡片项（用于设置子页面选项）
class SettingsRadioTile extends StatefulWidget {
  const SettingsRadioTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<SettingsRadioTile> createState() => _SettingsRadioTileState();
}

class _SettingsRadioTileState extends State<SettingsRadioTile> {
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
        selected: widget.selected,
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
              margin: const EdgeInsets.only(bottom: 10),
              padding: widget.contentPadding,
              decoration: BoxDecoration(
                color: _focused
                    ? (isDark ? AppColors.darkSurfaceHighest : AppColors.accentSubtle12)
                    : widget.selected
                        ? (isDark ? AppColors.darkSurfaceHighest : AppColors.accentSubtle12)
                        : (isDark ? AppColors.darkCard : AppColors.greyLight),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _focused
                      ? AppColors.hongguoRed
                      : widget.selected
                          ? AppColors.hongguoRed
                          : AppColors.transparent,
                  width: _focused ? 2.5 : (widget.selected ? 1.5 : 1.0),
                ),
              ),
              child: Row(
                children: [
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle(
                          style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: widget.selected || _focused
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: widget.selected || _focused
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
                  if (widget.selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.hongguoRed,
                      size: 22,
                    )
                  else if (_focused)
                    const Icon(
                      Icons.radio_button_unchecked_rounded,
                      color: AppColors.hongguoRed,
                      size: 22,
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
