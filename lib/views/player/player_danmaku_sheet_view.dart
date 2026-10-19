import 'package:flutter/material.dart';

import 'package:THLRedLook/models/danmaku/danmaku_models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class PlayerDanmakuSheetView extends StatefulWidget {
  const PlayerDanmakuSheetView({
    super.key,
    required this.enabled,
    required this.style,
    required this.onEnabledChanged,
    required this.onStyleChanged,
  });

  final bool enabled;
  final DanmakuStyle style;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<DanmakuStyle> onStyleChanged;

  static Future<void> show({
    required BuildContext context,
    required bool enabled,
    required DanmakuStyle style,
    required ValueChanged<bool> onEnabledChanged,
    required ValueChanged<DanmakuStyle> onStyleChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => PlayerDanmakuSheetView(
        enabled: enabled,
        style: style,
        onEnabledChanged: onEnabledChanged,
        onStyleChanged: onStyleChanged,
      ),
    );
  }

  @override
  State<PlayerDanmakuSheetView> createState() => _PlayerDanmakuSheetViewState();
}

class _PlayerDanmakuSheetViewState extends State<PlayerDanmakuSheetView> {
  late bool _enabled;
  late DanmakuStyle _style;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    _style = widget.style;
  }

  void _updateEnabled(bool val) {
    setState(() => _enabled = val);
    widget.onEnabledChanged(val);
  }

  void _updateStyle(DanmakuStyle next) {
    setState(() => _style = next);
    widget.onStyleChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;

    final fontSizeOptions = [
      {'label': '小 (0.8x)', 'val': 0.8},
      {'label': '标准 (1.0x)', 'val': 1.0},
      {'label': '大 (1.25x)', 'val': 1.25},
      {'label': '特大 (1.5x)', 'val': 1.5},
    ];

    final opacityOptions = [
      {'label': '40%', 'val': 0.4},
      {'label': '60%', 'val': 0.6},
      {'label': '80%', 'val': 0.8},
      {'label': '100%', 'val': 1.0},
    ];

    final areaOptions = [
      {'label': '1/4 屏', 'val': 0.25},
      {'label': '半屏', 'val': 0.5},
      {'label': '3/4 屏', 'val': 0.75},
      {'label': '全屏', 'val': 1.0},
    ];

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isLandscape ? 520 : 600,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.whiteWithAlpha(0.24),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.subtitles_rounded,
                      size: 20,
                      color: AppColors.hongguoRed,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '弹幕设置',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.white),
                      visualDensity: VisualDensity.compact,
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 1. 弹幕开关
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '显示弹幕',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.whiteWithAlpha(0.95),
                        ),
                      ),
                      const Spacer(),
                      Switch.adaptive(
                        key: const ValueKey('danmaku-sheet-switch'),
                        value: _enabled,
                        activeThumbColor: AppColors.white,
                        activeTrackColor: AppColors.hongguoRed,
                        onChanged: _updateEnabled,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. 实时预览条
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.blackWithAlpha(0.50),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.whiteWithAlpha(0.08)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '这是一条弹幕效果预览 🚀',
                    style: TextStyle(
                      fontSize: 15.0 * _style.fontSizeScale,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white.withValues(alpha: _style.opacity),
                      shadows: [
                        Shadow(
                          color: AppColors.black.withValues(alpha: _style.opacity * 0.85),
                          blurRadius: 3,
                          offset: const Offset(1, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 3. 字体大小
                _buildSectionHeader('字体大小', '${_style.fontSizeScale}x'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final opt in fontSizeOptions)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _buildChip(
                            key: ValueKey('danmaku-size-${opt['val']}'),
                            label: opt['label'] as String,
                            selected: (_style.fontSizeScale - (opt['val'] as double)).abs() < 0.05,
                            onSelected: () {
                              _updateStyle(_style.copyWith(fontSizeScale: opt['val'] as double));
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // 4. 不透明度
                _buildSectionHeader('不透明度', '${(_style.opacity * 100).toInt()}%'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final opt in opacityOptions)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _buildChip(
                            key: ValueKey('danmaku-opacity-${opt['val']}'),
                            label: opt['label'] as String,
                            selected: (_style.opacity - (opt['val'] as double)).abs() < 0.05,
                            onSelected: () {
                              _updateStyle(_style.copyWith(opacity: opt['val'] as double));
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // 5. 显示区域
                _buildSectionHeader('显示区域', optAreaLabel(_style.displayArea)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final opt in areaOptions)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _buildChip(
                            key: ValueKey('danmaku-area-${opt['val']}'),
                            label: opt['label'] as String,
                            selected: (_style.displayArea - (opt['val'] as double)).abs() < 0.05,
                            onSelected: () {
                              _updateStyle(_style.copyWith(displayArea: opt['val'] as double));
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String optAreaLabel(double area) {
    if (area <= 0.3) return '1/4 屏';
    if (area <= 0.6) return '半屏';
    if (area <= 0.8) return '3/4 屏';
    return '全屏';
  }

  Widget _buildSectionHeader(String title, String current) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.whiteWithAlpha(0.65),
          ),
        ),
        Text(
          current,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.hongguoRed,
          ),
        ),
      ],
    );
  }

  Widget _buildChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.hongguoRed : AppColors.darkCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.hongguoRed : AppColors.whiteWithAlpha(0.12),
            width: 1,
          ),
          boxShadow: selected
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
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? AppColors.white : AppColors.whiteWithAlpha(0.85),
          ),
        ),
      ),
    );
  }
}
