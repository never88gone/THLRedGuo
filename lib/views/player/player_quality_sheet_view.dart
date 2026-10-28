import 'package:flutter/material.dart';

import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 移动端画质选择半屏沉浸式抽屉面板
class PlayerQualitySheetView extends StatelessWidget {
  const PlayerQualitySheetView({
    super.key,
    required this.qualities,
    required this.selectedQuality,
    required this.actualQuality,
    required this.isLocal,
    required this.onQualitySelected,
  });

  final List<int> qualities;
  final int selectedQuality;
  final int actualQuality;
  final bool isLocal;
  final ValueChanged<int> onQualitySelected;

  static String qualityTitle(int quality) {
    if (quality == 0) return '自动模式';
    if (quality >= 1080) return '${quality}P 超清';
    if (quality >= 720) return '${quality}P 高清';
    return '${quality}P 标清';
  }

  static String qualitySubtitle(int quality) {
    if (quality == 0) return '优先 1080P，按片源实际可用清晰度播放';
    if (quality >= 1080) return '高清片源，画面细节更丰富';
    if (quality >= 720) return '高清画质，边缘清晰锐利，平衡效果与流畅度';
    return '低带宽省流首选，极速起播不卡顿';
  }

  @override
  Widget build(BuildContext context) {
    final available = qualities.isNotEmpty
        ? qualities
        : [if (actualQuality > 0) actualQuality];
    final options = {0, ...available.where((q) => q > 0)}.toList();

    // 按画质降序排列（1080P 在上，自动在最前）
    options.sort((a, b) {
      if (a == 0) return -1;
      if (b == 0) return 1;
      return b.compareTo(a);
    });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 3.5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.whiteWithAlpha(0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选择播放清晰度',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isLocal
                            ? '正在播放离线原画，画质偏好将在在线播放时生效'
                            : actualQuality > 0
                            ? '当前正在播放 ${qualityTitle(actualQuality)}'
                            : '默认优先 1080P，等待片源信息',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondaryDark,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final q = options[index];
                  final isSelected = q == selectedQuality;
                  final isCurrentActive =
                      !isLocal && (q == actualQuality && q > 0);

                  return InkWell(
                    key: ValueKey('quality-option-$q'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      onQualitySelected(q);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.hongguoRedWithAlpha(0.12)
                            : AppColors.darkSurfaceHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.hongguoRedWithAlpha(0.7)
                              : AppColors.whiteWithAlpha(0.04),
                          width: 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.hongguoRedWithAlpha(0.12),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      qualityTitle(q),
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? AppColors.hongguoRed
                                            : AppColors.textPrimaryDark,
                                      ),
                                    ),
                                    if (isCurrentActive) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.hongguoRed,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Text(
                                          '播放中',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  qualitySubtitle(q),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isSelected
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textTertiaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.hongguoRed,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
