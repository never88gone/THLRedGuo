import SwiftUI

// MARK: - 统一全局色彩系统 (全 App 所有颜色集中于此文件)
public enum TVColors {
    // MARK: - 核心品牌与高亮强调色
    public static let primary = Color.red
    public static let accent = Color.red
    public static let primaryHover = Color(red: 1.0, green: 0.25, blue: 0.3)
    public static let activeRed = Color(red: 0.95, green: 0.12, blue: 0.22)
    public static let activeRedHighlight = Color(red: 1.0, green: 0.35, blue: 0.45)
    public static let inactiveRed = Color(red: 0.80, green: 0.10, blue: 0.20)
    public static let playIconRed = Color(red: 1.0, green: 0.35, blue: 0.4)
    public static let historyAccentRed = Color(red: 0.65, green: 0.08, blue: 0.18)

    // MARK: - 全局背景与暗黑渐变 (纯黑到勃艮第深红)
    public static let background = Color(red: 0.05, green: 0.02, blue: 0.03)
    public static let bgGradTopLeading = Color(red: 0.03, green: 0.01, blue: 0.02)
    public static let bgGradCenter = Color(red: 0.08, green: 0.02, blue: 0.04)
    public static let bgGradBottomTrailing = Color(red: 0.17, green: 0.03, blue: 0.06)

    public static let backgroundGradient = LinearGradient(
        colors: [bgGradTopLeading, bgGradCenter, bgGradBottomTrailing],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 表面卡片与深色层次 (Surface & Cards)
    public static let surfaceDark = Color(red: 0.10, green: 0.10, blue: 0.12)
    public static let surfaceCard = Color(red: 0.16, green: 0.16, blue: 0.18)
    public static let surfaceFocused = Color(red: 0.22, green: 0.22, blue: 0.26)
    public static let surfaceLight = Color(red: 0.20, green: 0.20, blue: 0.22)
    public static let buttonNeutral = Color(red: 0.16, green: 0.14, blue: 0.18)
    public static let buttonFocusedGradStart = Color(red: 0.36, green: 0.18, blue: 0.25)
    public static let buttonFocusedGradEnd = Color(red: 0.24, green: 0.12, blue: 0.18)
    public static let drawerBackground = Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.96)

    // 重点操作按钮渐变
    public static let prominentGradStart = Color(red: 0.95, green: 0.22, blue: 0.28)
    public static let prominentGradEnd = Color(red: 0.78, green: 0.12, blue: 0.18)
    public static let prominentGradient = LinearGradient(
        colors: [prominentGradStart, prominentGradEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // 胶囊选中高亮渐变
    public static let capsuleSelectedGradient = LinearGradient(
        colors: [activeRed, activeRedHighlight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let capsuleDefaultGradient = LinearGradient(
        colors: [primary, inactiveRed],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // 剧集播放态渐变
    public static let episodeActiveGradient = LinearGradient(
        colors: [activeRed, activeRedHighlight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let episodeInactiveGradient = LinearGradient(
        colors: [primary.opacity(0.38), historyAccentRed.opacity(0.42)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 焦点边框与阴影 (Focus & Shadows)
    public static let focusedBorderColor = Color.red
    public static let focusedShadowColor = Color.red.opacity(0.65)
    public static let focusedShadowStrong = Color.red.opacity(0.85)
    public static let borderSubtle = Color.white.opacity(0.12)
    public static let borderSelected = Color.white.opacity(0.35)

    // MARK: - 文本排版与辅助指示色
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.75)
    public static let textMuted = Color.gray
    public static let vipAccent = Color.yellow
    public static let vipTextFocused = Color(red: 0.7, green: 0.45, blue: 0.0)
    public static let successGreen = Color.green
    public static let tagBackground = Color.black.opacity(0.4)
    public static let focusedTagBackground = Color.black.opacity(0.12)
}

// MARK: - SwiftUI Color 语义化拓展
public extension Color {
    enum TV {
        public static var primary: Color { TVColors.primary }
        public static var primaryHover: Color { TVColors.primaryHover }
        public static var background: Color { TVColors.background }
        public static var surfaceDark: Color { TVColors.surfaceDark }
        public static var surfaceCard: Color { TVColors.surfaceCard }
        public static var surfaceFocused: Color { TVColors.surfaceFocused }
        public static var textPrimary: Color { TVColors.textPrimary }
        public static var textSecondary: Color { TVColors.textSecondary }
        public static var textMuted: Color { TVColors.textMuted }
        public static var vipAccent: Color { TVColors.vipAccent }
    }
}

// MARK: - 全局色彩预览
#Preview("TV Colors Palette") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("TVColors Palette").font(.title.bold()).foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                ColorTile(name: "primary", color: TVColors.primary)
                ColorTile(name: "primaryHover", color: TVColors.primaryHover)
                ColorTile(name: "activeRed", color: TVColors.activeRed)
                ColorTile(name: "background", color: TVColors.background)
                ColorTile(name: "surfaceDark", color: TVColors.surfaceDark)
                ColorTile(name: "surfaceCard", color: TVColors.surfaceCard)
                ColorTile(name: "surfaceFocused", color: TVColors.surfaceFocused)
                ColorTile(name: "vipAccent", color: TVColors.vipAccent)
            }
        }
        .padding(40)
    }
    .background(TVColors.backgroundGradient)
}

private struct ColorTile: View {
    let name: String
    let color: Color

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
            Text(name)
                .font(.caption)
                .foregroundColor(.white)
        }
    }
}
