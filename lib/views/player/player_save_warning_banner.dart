import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

class PlayerSaveWarningBanner extends StatelessWidget {
  const PlayerSaveWarningBanner({
    super.key,
    required this.message,
    required this.onRetry,
    this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 52,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Material(
            key: const ValueKey('player-save-warning-bar'),
            color: AppColors.darkSurfaceHigh.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(10),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.sync_problem_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    key: const ValueKey('player-save-warning-retry'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onRetry,
                    child: const Text(
                      '重试',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.hongguoRed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (onDismiss != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      key: const ValueKey('player-save-warning-dismiss'),
                      onTap: onDismiss,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.textTertiaryDark,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
