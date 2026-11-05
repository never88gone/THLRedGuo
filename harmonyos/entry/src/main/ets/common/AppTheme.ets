/**
 * 糖葫芦Haw 全局视觉规范与色彩定义
 * 完全对齐 Flutter 端 AppColors
 */
export class AppColors {
  // 品牌核心主色
  static readonly hongguoRed: string = '#FF2442';
  static readonly hongguoRedLight: string = '#FF4863';
  static readonly hongguoRedDark: string = '#E01835';
  static readonly hongguoOrange: string = '#FF6433';
  static readonly hongguoGold: string = '#FFC028';
  static readonly hongguoAmber: string = '#FF9800';
  static readonly hongguoCyan: string = '#00E5FF';

  // 基础背景色彩
  static readonly bgDark: string = '#101114';
  static readonly bgCard: string = '#18191E';
  static readonly bgCardHover: string = '#22242B';
  static readonly bgElevated: string = '#2A2C34';
  static readonly bgDialog: string = '#1F2026';

  // 基础文字色彩
  static readonly textPrimary: string = '#FFFFFF';
  static readonly textSecondary: string = '#B3FFFFFF';
  static readonly textMuted: string = '#66FFFFFF';
  static readonly textDisabled: string = '#33FFFFFF';

  // 功能色
  static readonly success: string = '#00C853';
  static readonly warning: string = '#FFAB00';
  static readonly error: string = '#FF334B';
  static readonly info: string = '#2979FF';
  static readonly divider: string = '#1FFFFFFF';
}

export class AppDimensions {
  static readonly radiusSm: number = 6;
  static readonly radiusMd: number = 10;
  static readonly radiusLg: number = 16;
  static readonly radiusXl: number = 24;

  static readonly paddingSm: number = 8;
  static readonly paddingMd: number = 12;
  static readonly paddingLg: number = 16;
  static readonly paddingXl: number = 24;
}
