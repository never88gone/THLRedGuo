import 'package:flutter/material.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 全局统一微光发光与现代投影（拒绝生硬 Material 单边重阴影）
abstract final class AppShadows {
  /// 主品牌红微光发光（用于主 CTA 按钮悬浮、激活芯片）
  static const List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: AppColors.shadowPrimaryGlow,
      blurRadius: 18,
      spreadRadius: -2,
      offset: Offset(0, 6),
    ),
  ];

  /// 柔和现代卡片弥散微阴影（提升立体景深感）
  static const List<BoxShadow> softCard = [
    BoxShadow(
      color: AppColors.shadowSoftCard,
      blurRadius: 16,
      spreadRadius: 0,
      offset: Offset(0, 6),
    ),
  ];

  /// 悬浮胶囊微妙光晕
  static const List<BoxShadow> pillGlow = [
    BoxShadow(
      color: AppColors.shadowPillGlow,
      blurRadius: 10,
      spreadRadius: -1,
      offset: Offset(0, 3),
    ),
  ];
}
