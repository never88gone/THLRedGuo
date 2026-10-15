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

  // ==========================================
  // 3. 深色主题环境色彩 (Dark Mode Surfaces)
  // ==========================================
  /// 深色深邃背景（纯正影院级黑底）
  static const Color darkBackground = Color(0xFF0D0E13);
  /// 深色主面板/导航底色
  static const Color darkSurface = Color(0xFF15171F);
  /// 深色卡片/条目表面
  static const Color darkCard = Color(0xFF1C1F2A);
  /// 深色悬浮/弹窗表面
  static const Color darkSurfaceHigh = Color(0xFF242836);
  /// 深色抬升表面
  static const Color darkSurfaceElevated = Color(0xFF242836);
  /// 深色高亮微卡片
  static const Color darkSurfaceHighest = Color(0xFF2D3244);
  /// 深色描边与分隔线
  static const Color darkBorder = Color(0xFF262A38);
  /// 深色弱化边框
  static const Color darkBorderSubtle = Color(0xFF1E212E);

  // ==========================================
  // 4. 浅色主题环境色彩 (Light Mode Surfaces)
  // ==========================================
  /// 浅色干净浅灰背景
  static const Color lightBackground = Color(0xFFF6F7FB);
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
  static const Color darkSurfaceHighest70 = Color(0xB32D3244);
  /// 轻量遮罩纯黑半透底 (纯黑 20% 透明)
  static const Color blackSubtle20 = Color(0x33000000);

  // ==========================================
  // 10. 辅助透明度工厂函数（杜绝业务层硬编码）
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

  /// 深色影院级背景纵深氛围微渐变（顶部极暗红晕 -> 纯净影院黑）
  static const LinearGradient darkAtmosphere = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF161118),
      Color(0xFF0D0E13),
      Color(0xFF0A0B10),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  /// 高阶微光立体卡片渐变（顶部透亮光泽 -> 沉稳微暗底色）
  static const LinearGradient surfaceCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF222736),
      Color(0xFF181B24),
    ],
  );

  /// 激活卡片微光渐变（融入 10% 品牌红光的暗夜高光卡片）
  static const LinearGradient surfaceActiveCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2E1C24),
      Color(0xFF1E1720),
    ],
  );

  /// 磨砂玻璃/半透明卡片微光细边框渐变
  static const LinearGradient glassBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x38FFFFFF),
      Color(0x0AFFFFFF),
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
      Color(0x00000000),
      Color(0x20000000),
      Color(0x80000000),
      Color(0xE6000000),
    ],
    stops: [0.0, 0.4, 0.75, 1.0],
  );

  /// 播放器顶部状态栏平滑下落黑渐变
  static const LinearGradient playerTopMask = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xCC000000),
      Color(0x66000000),
      Color(0x00000000),
    ],
  );

  /// 播放器底部控制栏平滑上托黑渐变
  static const LinearGradient playerBottomMask = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xF0000000),
      Color(0x99000000),
      Color(0x00000000),
    ],
  );

  /// 底部导航栏磨砂渐变底色
  static const LinearGradient bottomNavGlass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xF215171F),
      Color(0xFA0D0E13),
    ],
  );
}

/// 全局统一微光发光与现代投影（拒绝生硬 Material 单边重阴影）
abstract final class AppShadows {
  /// 主品牌红微光发光（用于主 CTA 按钮悬浮、激活芯片）
  static const List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: Color(0x59FF2442),
      blurRadius: 18,
      spreadRadius: -2,
      offset: Offset(0, 6),
    ),
  ];

  /// 柔和现代卡片弥散微阴影（提升立体景深感）
  static const List<BoxShadow> softCard = [
    BoxShadow(
      color: Color(0x52000000),
      blurRadius: 16,
      spreadRadius: 0,
      offset: Offset(0, 6),
    ),
  ];

  /// 悬浮胶囊微妙光晕
  static const List<BoxShadow> pillGlow = [
    BoxShadow(
      color: Color(0x3DFF2442),
      blurRadius: 10,
      spreadRadius: -1,
      offset: Offset(0, 3),
    ),
  ];
}

/// 全局统一现代圆角系统（拒绝直角和过于僵硬的默认圆角，采用大圆角与连续曲率手感）
abstract final class AppRadii {
  /// 微小组件（标签、角标）：8.0
  static const double badge = 8.0;
  static final BorderRadius badgeBorder = BorderRadius.circular(badge);

  /// 中小卡片（选集按钮、分集方块）：14.0
  static const double episode = 14.0;
  static final BorderRadius episodeBorder = BorderRadius.circular(episode);

  /// 标准卡片与海报（短剧海报卡片、设置项卡片）：18.0
  static const double card = 18.0;
  static final BorderRadius cardBorder = BorderRadius.circular(card);

  /// 大卡片与弹窗浮层（Sheet、Dialog）：24.0
  static const double sheet = 24.0;
  static final BorderRadius sheetBorder = BorderRadius.circular(sheet);

  /// 极致胶囊形状（主播放按钮、分类 Pill、搜索栏）：999.0
  static const double pill = 999.0;
  static final BorderRadius pillBorder = BorderRadius.circular(pill);
}
