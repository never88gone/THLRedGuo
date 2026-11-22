import 'package:flutter/material.dart';

import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

class OfflinePlayerTopBar extends StatelessWidget {
  const OfflinePlayerTopBar({
    super.key,
    required this.drama,
    required this.episodeNumber,
    required this.onBack,
  });

  final Drama drama;
  final int episodeNumber;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.black80, AppColors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('offline-player-back'),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.white,
                  ),
                  onPressed: onBack,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        drama.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '第 $episodeNumber 集 · 本地离线播放',
                        style: const TextStyle(
                          color: AppColors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white20,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '离线无网络',
                    style: TextStyle(
                      color: AppColors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
