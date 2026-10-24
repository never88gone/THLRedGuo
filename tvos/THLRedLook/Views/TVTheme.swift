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
    public var isFocused: Bool = false
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public let action: () -> Void

    @FocusState private var internalIsFocused: Bool
    @Environment(\.isFocused) private var envIsFocused

    public init(
        title: String,
        icon: String? = nil,
        isProminent: Bool = false,
        isFocused: Bool = false,
        isExternalFocused: Bool? = nil,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isProminent = isProminent
        self.isFocused = isExternalFocused ?? isFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.action = action
    }

    public var body: some View {
        let activeFocused = isFocused || envIsFocused || internalIsFocused
        Button(action: action) {
            TVButtonLabel(
                title: title,
                icon: icon,
                isProminent: isProminent,
                isFocused: activeFocused
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($internalIsFocused)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            }
        }
    }
}

private struct TVButtonLabel: View {
    let title: String
    let icon: String?
    let isProminent: Bool
    let isFocused: Bool
    @Environment(\.isFocused) private var envIsFocused

    var body: some View {
        let effectiveFocused = isFocused || envIsFocused
        HStack(spacing: 10) {
            if let ic = icon {
                Image(systemName: ic)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(effectiveFocused ? .white : (isProminent ? .white : TVTheme.primary))
            }
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(effectiveFocused ? .white : TVTheme.textPrimary)
            }
        }
        .padding(.horizontal, title.isEmpty ? 20 : 28)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isProminent
                        ? (effectiveFocused ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.22, blue: 0.28), Color(red: 0.78, green: 0.12, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(TVTheme.primary))
                        : (effectiveFocused ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.36, green: 0.18, blue: 0.25), Color(red: 0.24, green: 0.12, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color(red: 0.16, green: 0.14, blue: 0.18)))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    effectiveFocused ? Color.white : (isProminent ? Color.clear : Color.white.opacity(0.12)),
                    lineWidth: effectiveFocused ? 3.0 : 1.0
                )
        )
        .scaleEffect(effectiveFocused ? 1.08 : 1.0)
        .shadow(
            color: effectiveFocused ? Color.red.opacity(0.85) : Color.clear,
            radius: effectiveFocused ? 16 : 0,
            x: 0,
            y: effectiveFocused ? 4 : 0
        )
        .animation(TVTheme.focusSpringAnimation, value: effectiveFocused)
    }
}

// 统一胶囊焦点按钮（分类栏、Tab、选集分段、筛选标签）
public struct TVCapsuleButton: View {
    public let title: String
    public var isSelected: Bool = false
    public var isFocused: Bool = false
    public var onFocused: (() -> Void)? = nil
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public var onLeftCommand: (() -> Void)? = nil
    public var onRightCommand: (() -> Void)? = nil
    public let action: () -> Void

    public init(
        title: String,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isExternalFocused: Bool? = nil,
        onFocused: (() -> Void)? = nil,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        onLeftCommand: (() -> Void)? = nil,
        onRightCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isFocused = isExternalFocused ?? isFocused
        self.onFocused = onFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.onLeftCommand = onLeftCommand
        self.onRightCommand = onRightCommand
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TVCapsuleButtonLabel(
                title: title,
                isSelected: isSelected,
                externalFocused: isFocused,
                onFocused: onFocused
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            } else if direction == .left {
                onLeftCommand?()
            } else if direction == .right {
                onRightCommand?()
            }
        }
    }
}

private struct TVCapsuleButtonLabel: View {
    let title: String
    let isSelected: Bool
    let externalFocused: Bool
    let onFocused: (() -> Void)?

    @Environment(\.isFocused) private var envIsFocused

    var isFocused: Bool {
        externalFocused || envIsFocused
    }

    var body: some View {
        Text(title)
            .font(.system(size: isFocused ? 19 : 17, weight: (isFocused || isSelected) ? .heavy : .medium))
            .foregroundColor(textColor)
            .padding(.horizontal, isFocused ? 28 : 24)
            .padding(.vertical, isFocused ? 13 : 11)
            .background(backgroundView)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderStrokeColor, lineWidth: borderWidth)
            )
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(color: shadowColor, radius: shadowRadius, y: isFocused ? 4 : 0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
            .onChange(of: isFocused) { focused in
                if focused {
                    onFocused?()
                }
            }
    }

    private var textColor: Color {
        if isFocused {
            return isSelected ? .white : .black
        }
        if isSelected {
            return .white
        }
        return Color.white.opacity(0.85)
    }

    private var borderStrokeColor: Color {
        if isFocused {
            return isSelected ? Color.white : TVTheme.focusedBorderColor
        }
        if isSelected {
            return Color.white.opacity(0.35)
        }
        return Color.white.opacity(0.12)
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return TVTheme.focusedCapsuleBorderWidth
        }
        if isSelected {
            return 2.0
        }
        return 1.0
    }

    private var shadowColor: Color {
        if isFocused {
            return isSelected ? Color.red.opacity(0.85) : TVTheme.focusedShadowColor
        }
        if isSelected {
            return Color.red.opacity(0.4)
        }
        return Color.clear
    }

    private var shadowRadius: CGFloat {
        if isFocused {
            return 16.0
        }
        if isSelected {
            return 8.0
        }
        return 0
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            if isSelected {
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.12, blue: 0.22), Color(red: 1.0, green: 0.35, blue: 0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(white: 0.95)
            }
        } else {
            if isSelected {
                LinearGradient(
                    colors: [Color.red, Color(red: 0.80, green: 0.10, blue: 0.20)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                TVTheme.surfaceCard
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
    public var isFocused: Bool = false
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public let action: () -> Void

    public init(
        episode: Episode,
        isCurrent: Bool = false,
        isFocused: Bool = false,
        isExternalFocused: Bool? = nil,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.episode = episode
        self.isCurrent = isCurrent
        self.isFocused = isExternalFocused ?? isFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TVEpisodeButtonLabel(
                episode: episode,
                isCurrent: isCurrent,
                externalFocused: isFocused
            )
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            }
        }
    }
}

private struct TVEpisodeButtonLabel: View {
    let episode: Episode
    let isCurrent: Bool
    let externalFocused: Bool

    @Environment(\.isFocused) private var envIsFocused

    var isFocused: Bool {
        externalFocused || envIsFocused
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: isFocused ? 13 : 11, weight: .bold))
                        .foregroundColor(isFocused ? .white : Color(red: 1.0, green: 0.35, blue: 0.4))
                }

                Text("\(episode.number)")
                    .font(.system(size: isFocused ? 28 : (isCurrent ? 24 : 22), weight: isFocused ? .heavy : (isCurrent ? .bold : .semibold)))
                    .foregroundColor(textColor)

                if episode.vip {
                    Text("VIP")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(vipTextColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(vipBackgroundView)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)

            if isCurrent && !isFocused {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .padding(8)
            }
        }
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderStrokeColor, lineWidth: borderWidth)
        )
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .shadow(color: shadowColor, radius: shadowRadius, y: isFocused ? 5 : 0)
        .animation(TVTheme.focusSpringAnimation, value: isFocused)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private var textColor: Color {
        if isFocused {
            return isCurrent ? .white : .black
        }
        if isCurrent {
            return Color(red: 1.0, green: 0.35, blue: 0.4)
        }
        return Color.white.opacity(0.85)
    }

    private var vipTextColor: Color {
        if isFocused {
            return isCurrent ? .yellow : Color(red: 0.7, green: 0.45, blue: 0.0)
        }
        return TVTheme.vipAccent
    }

    private var vipBackgroundView: some View {
        if isFocused {
            return isCurrent ? Color.black.opacity(0.4) : Color.black.opacity(0.12)
        }
        return Color.black.opacity(0.4)
    }

    private var borderStrokeColor: Color {
        if isFocused {
            return isCurrent ? Color.white : TVTheme.focusedBorderColor
        }
        if isCurrent {
            return Color.red
        }
        return Color.white.opacity(0.12)
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return TVTheme.focusedBorderWidth
        }
        if isCurrent {
            return 2.5
        }
        return 1.0
    }

    private var shadowColor: Color {
        if isFocused {
            return isCurrent ? Color.red.opacity(0.8) : TVTheme.focusedShadowColor
        }
        if isCurrent {
            return Color.red.opacity(0.45)
        }
        return Color.clear
    }

    private var shadowRadius: CGFloat {
        if isFocused {
            return 16.0
        }
        if isCurrent {
            return 8.0
        }
        return 0
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isFocused {
            if isCurrent {
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.12, blue: 0.22), Color(red: 1.0, green: 0.35, blue: 0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(white: 0.95)
            }
        } else {
            if isCurrent {
                LinearGradient(
                    colors: [Color.red.opacity(0.38), Color(red: 0.65, green: 0.08, blue: 0.18).opacity(0.42)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                TVTheme.surfaceCard
            }
        }
    }
}

// 统一排行榜大Tab按钮
public struct TVRankingBoardButton: View {
    public let board: RankingBoard
    public var isSelected: Bool = false
    public var isFocused: Bool = false
    public var onFocused: (() -> Void)? = nil
    public var onUpCommand: (() -> Void)? = nil
    public var onDownCommand: (() -> Void)? = nil
    public var onLeftCommand: (() -> Void)? = nil
    public var onRightCommand: (() -> Void)? = nil
    public let action: () -> Void

    public init(
        board: RankingBoard,
        isSelected: Bool = false,
        isFocused: Bool = false,
        isExternalFocused: Bool? = nil,
        onFocused: (() -> Void)? = nil,
        onUpCommand: (() -> Void)? = nil,
        onDownCommand: (() -> Void)? = nil,
        onLeftCommand: (() -> Void)? = nil,
        onRightCommand: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.board = board
        self.isSelected = isSelected
        self.isFocused = isExternalFocused ?? isFocused
        self.onFocused = onFocused
        self.onUpCommand = onUpCommand
        self.onDownCommand = onDownCommand
        self.onLeftCommand = onLeftCommand
        self.onRightCommand = onRightCommand
        self.action = action
    }

    @Environment(\.isFocused) private var envIsFocused

    public var body: some View {
        let activeFocused = isFocused || envIsFocused
        Button(action: action) {
            VStack(spacing: 6) {
                Text(board.name)
                    .font(.system(size: 20, weight: isSelected ? .black : .bold))
                    .foregroundColor(TVTheme.textPrimary)
                    .lineLimit(1)
                Text(board.description)
                    .font(.caption)
                    .foregroundColor(activeFocused ? TVTheme.textPrimary.opacity(0.9) : TVTheme.textSecondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(width: 240)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? (activeFocused ? TVTheme.primaryHover : TVTheme.primary) : (activeFocused ? TVTheme.surfaceFocused : TVTheme.surfaceCard))
            )
            .tvFocusBorder(isFocused: activeFocused, cornerRadius: 14)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focusEffectDisabled()
        .onMoveCommand { direction in
            if direction == .up {
                onUpCommand?()
            } else if direction == .down {
                onDownCommand?()
            } else if direction == .left {
                onLeftCommand?()
            } else if direction == .right {
                onRightCommand?()
            }
        }
        .onChange(of: activeFocused) { focused in
            if focused {
                onFocused?()
            }
        }
    }
}
