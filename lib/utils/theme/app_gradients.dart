import 'package:flutter/material.dart';
import 'package:THLRedLook/utils/theme/app_colors.dart';

/// 全局统一渐变设计系统（杜绝粗糙扁平，打造现代流媒体轻奢质感）
abstract final class AppGradients {
  /// 品牌主活力渐变（亮粉红 -> 活力红 -> 暖橙，用于主行动点 CTA、播放键、高亮标签）
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.hongguoRedLight,
      AppColors.hongguoRed,
      AppColors.hongguoOrange,
    ],
  );

  /// 品牌微光水平渐变
  static const LinearGradient primaryHorizontal = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      AppColors.hongguoRedLight,
      AppColors.hongguoOrange,
    ],
  );

  /// 金牌 VIP / 排行榜前三名耀金渐变
  static const LinearGradient gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.hongguoGold,
      AppColors.hongguoAmber,
    ],
  );

  /// 深色影院级背景纵深氛围微渐变（顶部暖橙微晕 -> 柔和温润暖调黑底）
  static const LinearGradient darkAtmosphere = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.darkAtmosphereTop,
      AppColors.darkAtmosphereMid,
      AppColors.darkBackground,
    ],
    stops: [0.0, 0.35, 1.0],
  );

  /// 高阶微光立体卡片渐变（顶部透亮光泽 -> 沉稳微暗底色）
  static const LinearGradient surfaceCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.surfaceCardGradStart,
      AppColors.surfaceCardGradEnd,
    ],
  );

  /// 激活卡片微光渐变（融入暖橙微光的暗夜高光卡片）
  static const LinearGradient surfaceActiveCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.surfaceActiveGradStart,
      AppColors.surfaceActiveGradEnd,
    ],
  );

  /// 磨砂玻璃/半透明卡片微光细边框渐变
  static const LinearGradient glassBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.glassBorderStart,
      AppColors.glassBorderEnd,
    ],
  );

  /// 激活状态渐变发光描边
  static const LinearGradient activeBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.hongguoRedLight,
      AppColors.hongguoOrange,
    ],
  );

  /// 电影海报沉浸式底部渐变遮罩（全平滑多阶曲线）
  static const LinearGradient posterOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.transparent,
      AppColors.posterOverlayMid20,
      AppColors.posterOverlayMid80,
      AppColors.playerMaskBottom,
    ],
    stops: [0.0, 0.4, 0.75, 1.0],
  );

  /// 播放器顶部状态栏平滑下落黑渐变
  static const LinearGradient playerTopMask = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.playerTopMaskStart,
      AppColors.playerTopMaskMid,
      AppColors.transparent,
    ],
  );

  /// 播放器底部控制栏平滑上托黑渐变
  static const LinearGradient playerBottomMask = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      AppColors.playerBottomMaskStart,
      AppColors.playerBottomMaskMid,
      AppColors.transparent,
    ],
  );

  /// 底部导航栏磨砂渐变底色（暖调暗夜质感）
  static const LinearGradient bottomNavGlass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.bottomNavGlassStart,
      AppColors.bottomNavGlassEnd,
    ],
  );

  /// 排行榜冠亚季军徽章渐变
  static const LinearGradient rankingRank1 = LinearGradient(
    colors: [AppColors.rankingGold1, AppColors.rankingGold2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient rankingRank2 = LinearGradient(
    colors: [AppColors.rankingSilver1, AppColors.rankingSilver2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient rankingRank3 = LinearGradient(
    colors: [AppColors.rankingBronze1, AppColors.rankingBronze2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 播放器填充样式背景渐变
  static const List<Color> playerFillThemeDarkColors = [
    AppColors.playerFillDark1,
    AppColors.playerFillDark2,
    AppColors.playerFillDark3,
  ];
  static const List<Color> playerFillThemePosterColors = [
    AppColors.playerFillPoster1,
    AppColors.playerFillPoster2,
    AppColors.playerFillPoster3,
  ];
}
