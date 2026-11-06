import SwiftUI

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
        isFocusedExternal || envIsFocused
    }

    var body: some View {
        configuration.label
            .foregroundColor(foregroundColors)
            .background(backgroundView)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? TVColors.focusedBorderColor : Color.white.opacity(0.12), lineWidth: isFocused ? TVTheme.focusedBorderWidth : 1.0)
            )
            .scaleEffect(isFocused ? TVTheme.defaultScale : 1.0)
            .shadow(color: isFocused ? TVColors.focusedShadowColor : Color.clear, radius: isFocused ? TVTheme.focusedShadowRadius : 0)
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
                TVColors.primaryHover
            case .plain:
                TVColors.surfaceFocused
            case .secondary:
                Color.white.opacity(0.3)
            case .destructive:
                Color.red
            }
        } else {
            switch variant {
            case .primary:
                TVColors.primary.opacity(0.4)
            case .plain:
                Color.white.opacity(0.08)
            case .secondary:
                TVColors.surfaceCard
            case .destructive:
                Color.red.opacity(0.5)
            }
        }
    }
}

#Preview("TvButtonStyle Showcase") {
    VStack(spacing: 20) {
        Button("Primary Button") {}
            .buttonStyle(TvButtonStyle(variant: .primary, isFocused: true))
        Button("Secondary Button") {}
            .buttonStyle(TvButtonStyle(variant: .secondary, isFocused: false))
    }
    .padding(50)
    .background(TVColors.background)
}
