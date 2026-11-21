import 'package:flutter/material.dart';

/// 全局统一色彩中心（糖葫芦Haw 品牌视觉设计规范）
/// 规则：除本文件外，整个工程禁止出现任何硬编码 Color 构造或 Colors 静态引用。
abstract final class AppColors {
  // ==========================================
  // 1. 品牌核心色彩 (Brand Accent)
  // ==========================================
  /// 品牌主色（明艳番茄红/活力红）
  static const Color hongguoRed = Color(0xFFFF2442);
  /// 品牌高亮/悬停浅红
  static const Color hongguoRedLight = Color(0xFFFF4863);
  /// 品牌深色/按下态深红
  static const Color hongguoRedDark = Color(0xFFE01835);
  /// 品牌辅助暖橙色（渐变高光）
  static const Color hongguoOrange = Color(0xFFFF6433);
  /// 暖金皇冠/精选角标
  static const Color hongguoGold = Color(0xFFFFC028);
  /// 琥珀金高光
  static const Color hongguoAmber = Color(0xFFFF9800);
  /// 极光蓝辅助色
  static const Color hongguoCyan = Color(0xFF00E5FF);

  // ==========================================
  // 2. 基础系统颜色 (Base Colors)
  // ==========================================
  static const Color transparent = Color(0x00000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color success = Color(0xFF00C853);
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFFF334B);
  static const Color info = Color(0xFF2979FF);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color greyLight = Color(0xFFEEEEEE);
  static const Color greyDark = Color(0xFF616161);
  static const Color blue = Color(0xFF2196F3);
  static const Color green = Color(0xFF4CAF50);
  static const Color red = Color(0xFFF44336);
  static const Color orange = Color(0xFFFF9800);
  static const Color amber = Color(0xFFFFC107);
  static const Color purple = Color(0xFF9C27B0);
  static const Color brown = Color(0xFF795548);

  // ==========================================
  // 3. 深色主题环境色彩 (Dark Mode Surfaces)
  // ==========================================
  /// 深色深邃背景（融入淡淡暖橙微调，告别冷黑压抑）
  static const Color darkBackground = Color(0xFF1F1714);
  /// 深色主面板/导航底色（暖木炭黑）
  static const Color darkSurface = Color(0xFF261D19);
  /// 深色卡片/条目表面
  static const Color darkCard = Color(0xFF2E221D);
  /// 深色悬浮/弹窗表面
  static const Color darkSurfaceHigh = Color(0xFF382923);
  /// 深色抬升表面
  static const Color darkSurfaceElevated = Color(0xFF382923);
  /// 深色高亮微卡片
  static const Color darkSurfaceHighest = Color(0xFF45322A);
  /// 深色描边与分隔线
  static const Color darkBorder = Color(0xFF3E2D26);
  /// 深色弱化边框
  static const Color darkBorderSubtle = Color(0xFF30231D);

  // ==========================================
  // 4. 浅色主题环境色彩 (Light Mode Surfaces)
  // ==========================================
  /// 浅色干净柔和背景（淡淡暖橙象牙柔白）
  static const Color lightBackground = Color(0xFFFAF7F2);
  /// 浅色白底表面
  static const Color lightSurface = Color(0xFFFFFFFF);
  /// 浅色卡片
  static const Color lightCard = Color(0xFFFFFFFF);
  /// 浅色次级面板
  static const Color lightSurfaceHigh = Color(0xFFEEF0F6);
  /// 浅色高亮小部件
  static const Color lightSurfaceHighest = Color(0xFFE4E7F0);
  /// 浅色细边框
  static const Color lightBorder = Color(0xFFE5E7EB);
  /// 浅色弱化线条
  static const Color lightBorderSubtle = Color(0xFFEDEDF2);

  // ==========================================
  // 5. 文字排版色彩 (Typography)
  // ==========================================
  /// 深色主标题
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  /// 深色次级说明
  static const Color textSecondaryDark = Color(0xFF9EA3B2);
  /// 深色占位符/弱化文本
  static const Color textTertiaryDark = Color(0xFF676C7D);
  /// 默认主文本（深色环境纯白）
  static const Color textPrimary = textPrimaryDark;
  /// 默认次级文本
  static const Color textSecondary = textSecondaryDark;
  /// 默认弱化文本
  static const Color textTertiary = textTertiaryDark;
  /// 浅色主标题
  static const Color textPrimaryLight = Color(0xFF1A1C24);
  /// 浅色次级说明
  static const Color textSecondaryLight = Color(0xFF5A6072);
  /// 浅色弱化文本
  static const Color textTertiaryLight = Color(0xFF959BAE);

  // ==========================================
  // 6. 视频播放器与全屏剧场专属色彩 (Player Scene)
  // ==========================================
  /// 播放器环境黑场
  static const Color playerSceneDark = Color(0xFF07090E);
  /// 播放器容器底色
  static const Color playerSurface = Color(0xFF0D121C);
  /// 顶部微暗遮罩渐变起止
  static const Color playerMaskTop = Color(0xAA000000);
  /// 底部深黑遮罩渐变起止
  static const Color playerMaskBottom = Color(0xE6000000);
  /// 半透明控制层毛玻璃底色
  static const Color playerControlsOverlay = Color(0x5C000000);
  /// 顶部/底部半透明胶囊按钮底色
  static const Color playerPillButton = Color(0x4D000000);
  /// 播放器覆盖按钮背景色
  static const Color playerOverlayButton = playerPillButton;
  /// 播放器进度条底槽颜色
  static const Color playerProgressInactive = Color(0x3DFFFFFF);
  /// 播放器缓存进度颜色
  static const Color playerProgressBuffered = Color(0x66FFFFFF);
  /// 播放器激活高亮颜色（品牌活力红）
  static const Color playerProgressActive = Color(0xFFFF2442);
  /// 弹幕开关激活背景
  static const Color danmakuActiveBg = Color(0xFFFF2442);
  /// 播放器手势 HUD 卡片半透明背景
  static const Color playerGestureHudBackground = Color(0xCC000000);
  /// 播放器手势 HUD 卡片边框微光
  static const Color playerGestureHudBorder = Color(0x1FFFFFFF);
  /// 播放器手势 HUD 阴影色彩
  static const Color playerGestureHudShadow = Color(0x73000000);
  /// 播放器手势 HUD 进度条底槽颜色
  static const Color playerGestureHudTrack = Color(0x3DFFFFFF);
  /// 播放器手势 HUD 进度高亮色（琥珀金/活力橙）
  static const Color playerGestureHudHighlight = Color(0xFFFF9800);
  /// 播放器手势 HUD 次级说明文本
  static const Color playerGestureHudTextSecondary = Color(0xB3FFFFFF);
  /// 播放器中央主播放按钮毛玻璃深色背景
  static const Color playerCenterMainBg = Color(0x73000000);
  /// 播放器中央主播放按钮悬停/高光背景 (融入微弱暖红微光)
  static const Color playerCenterMainBgHover = Color(0x8A1A0B0E);
  /// 播放器中央主播放按钮高光微白边框
  static const Color playerCenterMainBorder = Color(0x40FFFFFF);
  /// 播放器中央主播放按钮悬停边框
  static const Color playerCenterMainBorderHover = Color(0x8CFFFFFF);
  /// 播放器中央切集按钮毛玻璃背景
  static const Color playerCenterSkipBg = Color(0x4D000000);
  /// 播放器中央切集按钮悬停背景
  static const Color playerCenterSkipBgHover = Color(0x6E000000);
  /// 播放器中央切集按钮边框
  static const Color playerCenterSkipBorder = Color(0x26FFFFFF);
  /// 播放器中央切集按钮悬停边框
  static const Color playerCenterSkipBorderHover = Color(0x66FFFFFF);

  // ==========================================
  // 7. 电影大片视觉微光与粒子 (Cinematic Glow & Sparks)
  // ==========================================
  static const Color cinemaGlowCenter = Color(0xFFFFE082);
  static const Color cinemaGlowMid = Color(0xFFFF7043);
  static const Color cinemaGlowOuter = Color(0xFFFF2442);
  static const Color cinemaSteelBlue = Color(0xFF64B5F6);
  static const Color cinemaSilhouette = Color(0xFF0A0E18);
  static const Color cinemaSparkGold = Color(0xFFFFD54F);
  static const Color cinemaSparkOrange = Color(0xFFFF8A65);

  // ==========================================
  // 8. 九宫格手势锁专属色彩 (Pattern Lock Scene)
  // ==========================================
  static const Color patternDotNormal = Color(0xFFB0B3BD);
  static const Color patternDotNormalDark = Color(0xFF4A4E5D);
  static const Color patternDotRing = Color(0x339E9E9E);
  static const Color patternDotActive = Color(0xFFFF2442);
  static const Color patternHaloActive = Color(0x33FF2442);
  static const Color patternLineActive = Color(0xFFFF2442);
  static const Color patternDotError = Color(0xFFFF334B);
  static const Color patternHaloError = Color(0x33FF334B);
  static const Color patternLineError = Color(0xFFFF334B);

  // ==========================================
  // 9. 界面高频半透明场景常量（杜绝业务层动态计算）
  // ==========================================
  /// 选中的微高亮卡片背景 (品牌红 12% 透明)
  static const Color accentSubtle12 = Color(0x1FFF2442);
  /// 微弱品牌红背景 (品牌红 8% 透明)
  static const Color accentSubtle08 = Color(0x14FF2442);
  /// 边框微弱品牌红 (品牌红 40% 透明)
  static const Color accentBorder40 = Color(0x66FF2442);
  /// 滑块激活轨道弱红 (品牌红 35% 透明)
  static const Color accentTrack35 = Color(0x59FF2442);
  /// 成功态轻量浅绿背景 (成功绿 15% 透明)
  static const Color successSubtle15 = Color(0x2600C853);
  /// 深色微卡片半透底 (深色最高表面 70% 透明)
  static const Color darkSurfaceHighest70 = Color(0xB345322A);
  /// 轻量遮罩纯黑半透底 (纯黑 20% 透明)
  static const Color blackSubtle20 = Color(0x33000000);

  // ==========================================
  // 10. 标准半透明白色阶梯 (White with Opacity)
  // ==========================================
  static const Color white06 = Color(0x0FFFFFFF);
  static const Color white08 = Color(0x14FFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);
  static const Color white12 = Color(0x1FFFFFFF);
  static const Color white15 = Color(0x26FFFFFF);
  static const Color white20 = Color(0x33FFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white30 = Color(0x4DFFFFFF);
  static const Color white38 = Color(0x62FFFFFF);
  static const Color white40 = Color(0x66FFFFFF);
  static const Color white50 = Color(0x80FFFFFF);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white60 = Color(0x99FFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white80 = Color(0xCCFFFFFF);

  // ==========================================
  // 11. 标准半透明黑色阶梯 (Black with Opacity)
  // ==========================================
  static const Color black10 = Color(0x1A000000);
  static const Color black12 = Color(0x1F000000);
  static const Color black20 = Color(0x33000000);
  static const Color black24 = Color(0x3D000000);
  static const Color black25 = Color(0x40000000);
  static const Color black30 = Color(0x4D000000);
  static const Color black33 = Color(0x55000000);
  static const Color black35 = Color(0x59000000);
  static const Color black38 = Color(0x61000000);
  static const Color black40 = Color(0x66000000);
  static const Color black45 = Color(0x73000000);
  static const Color black46 = Color(0x77000000);
  static const Color black54 = Color(0x8A000000);
  static const Color black60 = Color(0x99000000);
  static const Color black80 = Color(0xCC000000);
  static const Color black85 = Color(0xD9000000);

  // ==========================================
  // 12. 业务特定场景颜色
  // ==========================================
  static const Color goldTagBg = Color(0x66FFC028);
  static const Color diagnosticErrorDark = Color(0xFF281414);
  static const Color diagnosticErrorDeeper = Color(0xFF1E0E0E);
  static const Color redShade50 = Color(0xFFFFEBEE);
  static const Color orangeShade200 = Color(0xFFFFCC80);
  static const Color brownShade800 = Color(0xFF4E342E);
  static const Color offlinePlayerPanel = Color(0xFF2B2F3D);
  static const Color feedOverlayDark = Color(0xD9222222);
  static const Color rankingGold1 = Color(0xFFFF3366);
  static const Color rankingGold2 = Color(0xFFFF5E3A);
  static const Color rankingSilver1 = Color(0xFFFF8C00);
  static const Color rankingSilver2 = Color(0xFFFFA500);
  static const Color rankingBronze1 = Color(0xFF00B4DB);
  static const Color rankingBronze2 = Color(0xFF0083B0);
  static const Color darkAtmosphereTop = Color(0xFF332018);
  static const Color darkAtmosphereMid = Color(0xFF241814);
  static const Color surfaceCardGradStart = Color(0xFF32241E);
  static const Color surfaceCardGradEnd = Color(0xFF231915);
  static const Color surfaceActiveGradStart = Color(0xFF42251B);
  static const Color surfaceActiveGradEnd = Color(0xFF2C1913);
  static const Color glassBorderStart = Color(0x38FFFFFF);
  static const Color glassBorderEnd = Color(0x0AFFFFFF);
  static const Color posterOverlayMid20 = Color(0x20000000);
  static const Color posterOverlayMid80 = Color(0x80000000);
  static const Color playerTopMaskStart = Color(0xCC000000);
  static const Color playerTopMaskMid = Color(0x66000000);
  static const Color playerBottomMaskStart = Color(0xF0000000);
  static const Color playerBottomMaskMid = Color(0x99000000);
  static const Color bottomNavGlassStart = Color(0xF5261D19);
  static const Color bottomNavGlassEnd = Color(0xFC1C1512);
  static const Color playerFillDark1 = Color(0xFF3A2420);
  static const Color playerFillDark2 = Color(0xFF221411);
  static const Color playerFillDark3 = Color(0xFF140B09);
  static const Color playerFillPoster1 = Color(0xFF8B2500);
  static const Color playerFillPoster2 = Color(0xFF5E1914);
  static const Color playerFillPoster3 = Color(0xFF1E0807);
  static const Color shadowPrimaryGlow = Color(0x59FF2442);
  static const Color shadowSoftCard = Color(0x52000000);
  static const Color shadowPillGlow = Color(0x3DFF2442);

  // ==========================================
  // 13. 辅助透明度工厂函数（杜绝业务层硬编码）
  // ==========================================
  /// 生成纯白半透明色
  static Color whiteWithAlpha(double alpha) =>
      Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));

  /// 生成纯黑半透明色
  static Color blackWithAlpha(double alpha) =>
      Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0));

  /// 生成品牌红半透明色
  static Color hongguoRedWithAlpha(double alpha) =>
      Color.fromRGBO(255, 36, 66, alpha.clamp(0.0, 1.0));

  /// 生成成功绿半透明色
  static Color successWithAlpha(double alpha) =>
      Color.fromRGBO(0, 200, 83, alpha.clamp(0.0, 1.0));
}
