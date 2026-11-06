import SwiftUI

// MARK: - 全局统一主题尺寸、动画与焦点样式系统
public enum TVTheme {
    // MARK: - 基础调色板桥接 (全部颜色收口至 TVColors.swift)
    public static var primary: Color { TVColors.primary }
    public static var accent: Color { TVColors.accent }
    public static var primaryHover: Color { TVColors.primaryHover }
    public static var background: Color { TVColors.background }
    public static var backgroundGradient: LinearGradient { TVColors.backgroundGradient }
    public static var surfaceDark: Color { TVColors.surfaceDark }
    public static var surfaceCard: Color { TVColors.surfaceCard }
    public static var surfaceFocused: Color { TVColors.surfaceFocused }
    public static var surfaceLight: Color { TVColors.surfaceLight }

    // MARK: - 焦点特效参数配置 (遵循 Apple TV HIG 与 10-foot 大屏体验)
    public static var focusedBorderColor: Color { TVColors.focusedBorderColor }
    public static let focusedBorderWidth: CGFloat = 4.0
    public static let focusedCapsuleBorderWidth: CGFloat = 3.5
    public static let focusedShadowRadius: CGFloat = 14.0
    public static var focusedShadowColor: Color { TVColors.focusedShadowColor }
    public static let defaultScale: CGFloat = 1.06
    public static let cardScale: CGFloat = 1.06
    public static let circleScale: CGFloat = 1.10
    public static let animationDuration: Double = 0.25
    public static let focusSpringAnimation: Animation = .spring(response: 0.25, dampingFraction: 0.8)

    // MARK: - 文字排版颜色桥接
    public static var textPrimary: Color { TVColors.textPrimary }
    public static var textSecondary: Color { TVColors.textSecondary }
    public static var textMuted: Color { TVColors.textMuted }
    public static var vipAccent: Color { TVColors.vipAccent }
}

#Preview("TVTheme System") {
    VStack(spacing: 20) {
        Text("TVTheme System Active")
            .font(.title2.bold())
            .foregroundColor(TVTheme.textPrimary)
        Text("遵循客厅十英尺大屏焦点视觉与色彩规范")
            .font(.subheadline)
            .foregroundColor(TVTheme.textSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(TVTheme.backgroundGradient)
}
