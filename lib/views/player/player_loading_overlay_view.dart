import 'package:flutter/material.dart';

import 'package:THLRedLook/core/bridge/core_bridge.dart';
import 'package:THLRedLook/models/catalog/models.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';
import 'package:THLRedLook/views/common/widgets.dart';

/// 播放器缓冲与换集加载中遮罩视图
class PlayerLoadingOverlayView extends StatelessWidget {
  const PlayerLoadingOverlayView({
    super.key,
    required this.drama,
    required this.repository,
    required this.loadingMessage,
  });

  final Drama drama;
  final AppRepository repository;
  final String loadingMessage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.blackWithAlpha(0.60),
      ),
      child: Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Hero(
                tag: 'drama-cover-${drama.id}',
                child: Container(
                  width: 104,
                  height: 156,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.black46,
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: DramaCover(
                    drama: drama,
                    repository: repository,
                    radius: 14,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.hongguoRed,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                loadingMessage,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
