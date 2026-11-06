import SwiftUI

// MARK: - 统一圆形焦点边框修饰器
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
                    .stroke(isFocused ? TVColors.focusedBorderColor : Color.clear, lineWidth: lineWidth)
            )
            .shadow(
                color: isFocused ? TVColors.focusedShadowColor : Color.black.opacity(0.4),
                radius: isFocused ? 16 : 4,
                y: isFocused ? 4 : 2
            )
            .scaleEffect(isFocused ? scale : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
            .focusEffectDisabled()
    }
}

public extension View {
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
}

#Preview("TVCircleFocusModifier") {
    Image(systemName: "play.fill")
        .font(.system(size: 24))
        .padding(24)
        .background(Circle().fill(TVColors.primary))
        .tvCircleFocus(isFocused: true)
        .padding(60)
        .background(TVColors.background)
}
