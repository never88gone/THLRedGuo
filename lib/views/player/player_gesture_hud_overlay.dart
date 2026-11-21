import 'package:flutter/material.dart';

import 'package:THLRedLook/core/player/player_interactions.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 播放器手势调节反馈浮层（快进快退/亮度/音量 HUD 卡片）
class PlayerGestureHudOverlay extends StatelessWidget {
  const PlayerGestureHudOverlay({super.key, required this.interactions});

  final PlayerInteractions interactions;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: interactions,
      builder: (context, _) {
        final hud = interactions.hudState;
        if (hud.type == SwipeAction.none) {
          return const SizedBox.shrink();
        }

        return IgnorePointer(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: hud.type == SwipeAction.seek
                  ? _buildSeekCard(hud)
                  : hud.type == SwipeAction.brightness
                  ? _buildBrightnessCard(hud)
                  : hud.type == SwipeAction.volume
                  ? _buildVolumeCard(hud)
                  : const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeekCard(GestureHudState hud) {
    final isForward = hud.deltaSeconds >= 0;
    final totalSec = hud.duration.inSeconds.toDouble();
    final posSec = hud.position.inSeconds.toDouble().clamp(
      0.0,
      totalSec > 0 ? totalSec : 0.0,
    );
    final ratio = totalSec > 0 ? (posSec / totalSec).clamp(0.0, 1.0) : 0.0;
    final sign = hud.deltaSeconds > 0 ? '+' : '';

    return Container(
      key: const ValueKey('seek-hud-card'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.playerGestureHudBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.playerGestureHudBorder, width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.playerGestureHudShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward
                    ? Icons.fast_forward_rounded
                    : Icons.fast_rewind_rounded,
                color: AppColors.white,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                '$sign${hud.deltaSeconds}s',
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatPosition(posSec),
                style: const TextStyle(
                  color: AppColors.playerGestureHudHighlight,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                ' / ${formatPosition(totalSec)}',
                style: const TextStyle(
                  color: AppColors.playerGestureHudTextSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 3.5,
                backgroundColor: AppColors.playerGestureHudTrack,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.playerGestureHudHighlight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrightnessCard(GestureHudState hud) {
    final percent = (hud.value * 100).round().clamp(0, 100);
    return Container(
      key: const ValueKey('brightness-hud-card'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.playerGestureHudBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.playerGestureHudBorder, width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.playerGestureHudShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hud.value > 0.5
                ? Icons.brightness_7_rounded
                : Icons.brightness_medium_rounded,
            color: AppColors.white,
            size: 26,
          ),
          const SizedBox(height: 6),
          Text(
            '$percent%',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: hud.value.clamp(0.0, 1.0),
                minHeight: 3.5,
                backgroundColor: AppColors.playerGestureHudTrack,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeCard(GestureHudState hud) {
    final percent = (hud.value * 100).round().clamp(0, 100);
    final IconData icon;
    if (percent == 0) {
      icon = Icons.volume_off_rounded;
    } else if (percent < 30) {
      icon = Icons.volume_mute_rounded;
    } else if (percent < 70) {
      icon = Icons.volume_down_rounded;
    } else {
      icon = Icons.volume_up_rounded;
    }

    return Container(
      key: const ValueKey('volume-hud-card'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.playerGestureHudBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.playerGestureHudBorder, width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.playerGestureHudShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.white, size: 26),
          const SizedBox(height: 6),
          Text(
            percent == 0 ? '静音' : '$percent%',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: hud.value.clamp(0.0, 1.0),
                minHeight: 3.5,
                backgroundColor: AppColors.playerGestureHudTrack,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
