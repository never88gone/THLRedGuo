import SwiftUI

// 全局统一主题色、尺寸、动画与焦点样式系统
public enum TVTheme {
    // 基础调色板 (纯深色架构，绝无半透明泛白)
    public static let primary = Color.red
    public static let accent = Color.red
    public static let primaryHover = Color(red: 1.0, green: 0.25, blue: 0.3)
    public static let background = Color(red: 0.05, green: 0.02, blue: 0.03)
    
    // 全局背景渐变 (深邃纯黑到高级典雅暗红/勃艮第红)
    public static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.01, blue: 0.02),
            Color(red: 0.08, green: 0.02, blue: 0.04),
            Color(red: 0.17, green: 0.03, blue: 0.06)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public static let surfaceDark = Color(red: 0.10, green: 0.10, blue: 0.12)
    public static let surfaceCard = Color(red: 0.16, green: 0.16, blue: 0.18)
    public static let surfaceFocused = Color(red: 0.22, green: 0.22, blue: 0.26)
    public static let surfaceLight = Color(red: 0.20, green: 0.20, blue: 0.22)

    // 焦点特效配置 (遵循 Apple TV HIG 与 thldytv 规范)
    public static let focusedBorderColor = Color.red
    public static let focusedBorderWidth: CGFloat = 4.0
    public static let focusedCapsuleBorderWidth: CGFloat = 3.5
    public static let focusedShadowRadius: CGFloat = 14.0
    public static let focusedShadowColor = Color.red.opacity(0.65)
    public static let defaultScale: CGFloat = 1.06
    public static let cardScale: CGFloat = 1.06
    public static let circleScale: CGFloat = 1.10
    public static let animationDuration: Double = 0.25
    public static let focusSpringAnimation: Animation = .spring(response: 0.25, dampingFraction: 0.8)

    // 文字颜色
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.75)
    public static let textMuted = Color.gray
    public static let vipAccent = Color.yellow
}

// 彻底剥离 tvOS 系统原生白光/白卡片滤镜的纯净 ButtonStyle
public struct TVZeroHighlightButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// 适用于 tvOS 遥控器聚焦的按钮变体
public enum TvButtonVariant {
    case primary      // 核心操作：主题红高亮
    case destructive  // 危险操作
    case secondary    // 辅助卡片
    case plain        // 弱化/半透明卡片
}

/// 适用于 tvOS 遥控器聚焦的标准卡片/按钮样式（参考 thldytv 规范）
public struct TvButtonStyle: ButtonStyle {
    public var variant: TvButtonVariant = .primary
    public var cornerRadius: CGFloat = 14
    public var isFocused: Bool = false

    public init(variant: TvButtonVariant = .primary, cornerRadius: CGFloat = 14, isFocused: Bool = false) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.isFocused = isFocused
    }

    public func makeBody(configuration: Configuration) -> some View {
        TvButtonHelper(
            configuration: configuration,
            variant: variant,
            cornerRadius: cornerRadius,
            isFocusedExternal: isFocused
        )
    }
}

private struct TvButtonHelper: View {
    let configuration: ButtonStyle.Configuration
    let variant: TvButtonVariant
    let cornerRadius: CGFloat
    let isFocusedExternal: Bool

    @Environment(\.isFocused) var envIsFocused

    var isFocused: Bool {
        return isFocusedExternal || envIsFocused
    }

    var body: some View {
        configuration.label
            .foregroundColor(foregroundColors)
            .background(backgroundView)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? TVTheme.focusedBorderColor : Color.white.opacity(0.12), lineWidth: isFocused ? TVTheme.focusedBorderWidth : 1.0)
            )
            .scaleEffect(isFocused ? TVTheme.defaultScale : 1.0)
            .shadow(color: isFocused ? TVTheme.focusedShadowColor : Color.clear, radius: isFocused ? TVTheme.focusedShadowRadius : 0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }

    private var foregroundColors: Color {
        if isFocused {
            return .white
        }
        switch variant {
        case .primary:
            return .white
        case .plain:
            return .white.opacity(0.85)
        case .secondary:
            return .white
        case .destructive:
            return .white
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            switch variant {
            case .primary:
                TVTheme.primaryHover
            case .plain:
                TVTheme.surfaceFocused
            case .secondary:
                Color.white.opacity(0.3)
            case .destructive:
                Color.red
            }
        } else {
            switch variant {
            case .primary:
                TVTheme.primary.opacity(0.4)
            case .plain:
                Color.white.opacity(0.08)
            case .secondary:
                TVTheme.surfaceCard
            case .destructive:
                Color.red.opacity(0.5)
            }
        }
    }
}

/// 适用于全屏捕获层和透明容器的按钮样式（参考 thldytv 规范）
public struct TvTransparentButtonStyle: ButtonStyle {
    public var cornerRadius: CGFloat = 16
    public var isFocused: Bool = false
    public var focusedScale: CGFloat = 1.0

    public init(cornerRadius: CGFloat = 16, isFocused: Bool = false, focusedScale: CGFloat = 1.0) {
        self.cornerRadius = cornerRadius
        self.isFocused = isFocused
        self.focusedScale = focusedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        TvTransparentButtonHelper(
            configuration: configuration,
            cornerRadius: cornerRadius,
            isFocusedExternal: isFocused,
            focusedScale: focusedScale
        )
    }
}

private struct TvTransparentButtonHelper: View {
    let configuration: ButtonStyle.Configuration
    let cornerRadius: CGFloat
    let isFocusedExternal: Bool
    let focusedScale: CGFloat

    @Environment(\.isFocused) var envIsFocused

    var isFocused: Bool {
        return isFocusedExternal || envIsFocused
    }

    var body: some View {
        configuration.label
            .background(Color.clear)
            .cornerRadius(cornerRadius)
            .scaleEffect(isFocused ? focusedScale : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }
}

// 统一矩形焦点边框修饰器
public struct TVFocusBorderModifier: ViewModifier {
    public var isFocused: Bool
    public var cornerRadius: CGFloat
    public var lineWidth: CGFloat
    public var scale: CGFloat

    public init(
        isFocused: Bool,
        cornerRadius: CGFloat = 12,
        lineWidth: CGFloat = TVTheme.focusedBorderWidth,
        scale: CGFloat = TVTheme.defaultScale
    ) {
        self.isFocused = isFocused
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.scale = scale
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? TVTheme.focusedBorderColor : Color.clear, lineWidth: lineWidth)
            )
            .shadow(
                color: isFocused ? TVTheme.focusedShadowColor : Color.clear,
                radius: isFocused ? TVTheme.focusedShadowRadius : 0,
                y: isFocused ? 4 : 0
            )
            .scaleEffect(isFocused ? scale : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
            .focusEffectDisabled()
    }
}

// 统一胶囊焦点边框修饰器
public struct TVCapsuleFocusModifier: ViewModifier {
    public var isFocused: Bool
    public var lineWidth: CGFloat
    public var scale: CGFloat

    public init(
        isFocused: Bool,
        lineWidth: CGFloat = TVTheme.focusedCapsuleBorderWidth,
        scale: CGFloat = TVTheme.defaultScale
    ) {
        self.isFocused = isFocused
        self.lineWidth = lineWidth
        self.scale = scale
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                Capsule()
                    .stroke(isFocused ? TVTheme.focusedBorderColor : Color.clear, lineWidth: lineWidth)
            )
            .shadow(
                color: isFocused ? TVTheme.focusedShadowColor : Color.clear,
                radius: isFocused ? 12 : 0
            )
            .scaleEffect(isFocused ? scale : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
            .focusEffectDisabled()
    }
}

// 统一圆形焦点边框修饰器
public struct TVCircleFocusModifier: ViewModifier {
    public var isFocused: Bool
    public var lineWidth: CGFloat
    public var scale: CGFloat

    public init(
        isFocused: Bool,
        lineWidth: CGFloat = 4.5,
        scale: CGFloat = TVTheme.circleScale
    ) {
        self.isFocused = isFocused
        self.lineWidth = lineWidth
        self.scale = scale
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(isFocused ? TVTheme.focusedBorderColor : Color.clear, lineWidth: lineWidth)
            )
            .shadow(
                color: isFocused ? TVTheme.focusedShadowColor : Color.black.opacity(0.4),
                radius: isFocused ? 16 : 4,
                y: isFocused ? 4 : 2
            )
            .scaleEffect(isFocused ? scale : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
            .focusEffectDisabled()
    }
}

public extension View {
    func tvFocusBorder(
        isFocused: Bool,
        cornerRadius: CGFloat = 12,
        lineWidth: CGFloat = TVTheme.focusedBorderWidth,
        scale: CGFloat = TVTheme.defaultScale
    ) -> some View {
        self.modifier(TVFocusBorderModifier(
            isFocused: isFocused,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            scale: scale
        ))
    }

    func tvCapsuleFocus(
        isFocused: Bool,
        lineWidth: CGFloat = TVTheme.focusedCapsuleBorderWidth,
        scale: CGFloat = TVTheme.defaultScale
    ) -> some View {
        self.modifier(TVCapsuleFocusModifier(
            isFocused: isFocused,
            lineWidth: lineWidth,
            scale: scale
        ))
    }

    func tvCircleFocus(
        isFocused: Bool,
        lineWidth: CGFloat = 4.5,
        scale: CGFloat = TVTheme.circleScale
    ) -> some View {
        self.modifier(TVCircleFocusModifier(
            isFocused: isFocused,
            lineWidth: lineWidth,
            scale: scale
        ))
    }

    func tvPanelStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(TVTheme.surfaceDark)
            )
    }
}

// 统一标准矩形焦点按钮
public struct TVButton: View {
    public let title: String
    public var icon: String? = nil
    public var isProminent: Bool = false
    public var isExternalFocused: Bool? = nil
    public let action: () -> Void

    @Environment(\.isFocused) private var envIsFocused: Bool

    private var isFocused: Bool {
        isExternalFocused ?? envIsFocused
    }

    public init(title: String, icon: String? = nil, isProminent: Bool = false, isExternalFocused: Bool? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isProminent = isProminent
        self.isExternalFocused = isExternalFocused
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 18, weight: .bold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .padding(.horizontal, title.isEmpty ? 20 : 28)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isProminent ? (isFocused ? TVTheme.primaryHover : TVTheme.primary) : (isFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard))
            )
            .foregroundColor(TVTheme.textPrimary)
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 14)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
    }
}

// 统一胶囊焦点按钮（分类栏、Tab、筛选标签）
public struct TVCapsuleButton: View {
    public let title: String
    public var isSelected: Bool = false
    public var isExternalFocused: Bool? = nil
    public var onFocused: (() -> Void)? = nil
    public let action: () -> Void

    @Environment(\.isFocused) private var envIsFocused: Bool

    private var isFocused: Bool {
        isExternalFocused ?? envIsFocused
    }

    public init(
        title: String,
        isSelected: Bool = false,
        isExternalFocused: Bool? = nil,
        onFocused: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isExternalFocused = isExternalFocused
        self.onFocused = onFocused
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                .foregroundColor(TVTheme.textPrimary)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(
                    isSelected ? (isFocused ? TVTheme.primaryHover : TVTheme.primary) : (isFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard)
                )
                .clipShape(Capsule())
                .tvCapsuleFocus(isFocused: isFocused)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onChange(of: envIsFocused) { focused in
            if focused {
                onFocused?()
            }
        }
    }
}

// 统一圆形焦点按钮（播放器核心三按键）
public struct TVPlayerCircleButton: View {
    public let icon: String
    public var size: CGFloat = 36
    public var padding: CGFloat = 20
    public var isProminent: Bool = false
    public var forceFocused: Bool = false
    public let action: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        icon: String,
        size: CGFloat = 36,
        padding: CGFloat = 20,
        isProminent: Bool = false,
        forceFocused: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.padding = padding
        self.isProminent = isProminent
        self.forceFocused = forceFocused
        self.action = action
    }

    public var body: some View {
        let effectiveFocused = isFocused || forceFocused
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(TVTheme.textPrimary)
                .padding(padding)
                .background(
                    Circle()
                        .fill(isProminent ? (effectiveFocused ? TVTheme.primaryHover : TVTheme.primary) : (effectiveFocused ? TVTheme.surfaceFocused : Color.black.opacity(0.85)))
                )
                .tvCircleFocus(isFocused: effectiveFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

// 统一剧集网格按钮
public struct TVEpisodeButton: View {
    public let episode: Episode
    public var isCurrent: Bool = false
    public let action: () -> Void

    @FocusState private var isFocused: Bool

    public init(episode: Episode, isCurrent: Bool = false, action: @escaping () -> Void) {
        self.episode = episode
        self.isCurrent = isCurrent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text("\(episode.number)")
                    .font(.system(size: 22, weight: isCurrent ? .black : .bold))
                    .foregroundColor(isCurrent ? TVTheme.primary : TVTheme.textPrimary)
                if episode.vip {
                    Text("VIP")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TVTheme.vipAccent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isCurrent ? TVTheme.primary.opacity(0.35) : (isFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard))
            )
            .tvFocusBorder(
                isFocused: isFocused,
                cornerRadius: 14,
                lineWidth: TVTheme.focusedBorderWidth
            )
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

// 统一排行榜大Tab按钮
public struct TVRankingBoardButton: View {
    public let board: RankingBoard
    public var isSelected: Bool = false
    public var isExternalFocused: Bool? = nil
    public var onFocused: (() -> Void)? = nil
    public let action: () -> Void

    @Environment(\.isFocused) private var envIsFocused: Bool

    private var isFocused: Bool {
        isExternalFocused ?? envIsFocused
    }

    public init(
        board: RankingBoard,
        isSelected: Bool = false,
        isExternalFocused: Bool? = nil,
        onFocused: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.board = board
        self.isSelected = isSelected
        self.isExternalFocused = isExternalFocused
        self.onFocused = onFocused
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(board.name)
                    .font(.system(size: 20, weight: isSelected ? .black : .bold))
                    .foregroundColor(TVTheme.textPrimary)
                Text(board.description)
                    .font(.caption)
                    .foregroundColor(isFocused ? TVTheme.textPrimary.opacity(0.9) : TVTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 160)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? (isFocused ? TVTheme.primaryHover : TVTheme.primary) : (isFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard))
            )
            .tvFocusBorder(isFocused: isFocused, cornerRadius: 14)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onChange(of: envIsFocused) { focused in
            if focused {
                onFocused?()
            }
        }
    }
}
