import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 具备遥控器按键直接切换与电视焦点感知的设置开关项
class SettingsSwitchTile extends StatefulWidget {
  const SettingsSwitchTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
    this.focusNode,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry contentPadding;

  @override
  State<SettingsSwitchTile> createState() => _SettingsSwitchTileState();
}

class _SettingsSwitchTileState extends State<SettingsSwitchTile> {
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

  void _toggle() {
    if (widget.onChanged != null) {
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.onChanged != null,
      onFocusChange: _handleFocusChange,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _toggle();
            return null;
          },
        ),
      },
      child: Semantics(
        toggled: widget.value,
        enabled: widget.onChanged != null,
        focused: _focused,
        child: MouseRegion(
          cursor: widget.onChanged != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              padding: widget.contentPadding,
              decoration: BoxDecoration(
                color: _focused
                    ? (isDark ? AppColors.darkSurfaceHighest : AppColors.accentSubtle12)
                    : AppColors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _focused
                      ? AppColors.hongguoRed
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
                            : theme.iconTheme.color,
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
                                fontWeight: _focused
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
                  ExcludeFocus(
                    child: Switch.adaptive(
                      value: widget.value,
                      onChanged: widget.onChanged,
                      activeThumbColor: AppColors.white,
                      activeTrackColor: AppColors.hongguoRed,
                    ),
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
