import 'package:flutter/material.dart';

import 'package:THLRedLook/core/player/playback_preferences.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class PlayerSpeedSheetView extends StatefulWidget {
  const PlayerSpeedSheetView({
    super.key,
    required this.currentSpeed,
    required this.onSpeedSelected,
  });

  final double currentSpeed;
  final ValueChanged<double> onSpeedSelected;

  static Future<double?> show({
    required BuildContext context,
    required double currentSpeed,
    required ValueChanged<double> onSpeedSelected,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      builder: (sheetContext) => PlayerSpeedSheetView(
        currentSpeed: currentSpeed,
        onSpeedSelected: onSpeedSelected,
      ),
    );
  }

  @override
  State<PlayerSpeedSheetView> createState() => _PlayerSpeedSheetViewState();
}

class _PlayerSpeedSheetViewState extends State<PlayerSpeedSheetView> {
  late double _selectedSpeed;

  @override
  void initState() {
    super.initState();
    _selectedSpeed = widget.currentSpeed;
  }

  void _chooseSpeed(double speed) {
    if (_selectedSpeed == speed) return;
    setState(() {
      _selectedSpeed = speed;
    });
    widget.onSpeedSelected(speed);
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) {
        Navigator.pop(context, speed);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isLandscape ? 460 : 520,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
                        Icons.speed_rounded,
                        size: 20,
                        color: AppColors.hongguoRed,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      '播放倍速',
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
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.start,
                  children: [
                    for (final speed in playbackSpeeds) ...[
                      ChoiceChip(
                        key: ValueKey('sheet-speed-$speed'),
                        label: Text(
                          '${speed}x${speed == 1.0 ? ' (正常)' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: speed == _selectedSpeed
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: speed == _selectedSpeed
                                ? AppColors.white
                                : AppColors.whiteWithAlpha(0.85),
                          ),
                        ),
                        selected: speed == _selectedSpeed,
                        selectedColor: AppColors.hongguoRed,
                        backgroundColor: AppColors.darkCard,
                        side: BorderSide(
                          color: speed == _selectedSpeed
                              ? AppColors.hongguoRed
                              : AppColors.whiteWithAlpha(0.12),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        showCheckmark: false,
                        onSelected: (_) => _chooseSpeed(speed),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
