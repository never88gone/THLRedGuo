import 'package:flutter/material.dart';

import 'package:THLRedLook/core/cast/haw_cast_models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class HawCastAirPlayCard extends StatelessWidget {
  const HawCastAirPlayCard({
    super.key,
    required this.cardBg,
    required this.borderColor,
    required this.onTap,
  });

  final Color cardBg;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('cast-airplay-video-card'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.airplay_rounded, color: colors.onSurface),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Apple AirPlay 视频投屏',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '仅推送纯视频画面至电视/接收端，不镜像手机屏幕',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HawCastDeviceCard extends StatelessWidget {
  const HawCastDeviceCard({
    super.key,
    required this.device,
    required this.cardBg,
    required this.borderColor,
    required this.isConnected,
    required this.isBusy,
    required this.onTap,
  });

  final HawCastDevice device;
  final Color cardBg;
  final Color borderColor;
  final bool isConnected;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isConnected ? AppColors.hongguoRed : borderColor,
              width: isConnected ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isConnected
                      ? AppColors.hongguoRedWithAlpha(0.15)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.tv_rounded,
                  color: isConnected ? AppColors.hongguoRed : colors.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${device.address} · ${device.supportsEncrypted ? '支持解密播放' : '在线直连'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.hongguoRed,
                  ),
                )
              else if (isConnected)
                const Text(
                  '投屏中',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.hongguoRed,
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
