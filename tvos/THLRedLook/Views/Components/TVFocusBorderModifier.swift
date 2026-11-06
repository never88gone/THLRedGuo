import SwiftUI

// MARK: - 统一矩形焦点边框修饰器
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
                    .stroke(isFocused ? TVColors.focusedBorderColor : Color.clear, lineWidth: lineWidth)
            )
            .shadow(
                color: isFocused ? TVColors.focusedShadowColor : Color.clear,
                radius: isFocused ? TVTheme.focusedShadowRadius : 0,
                y: isFocused ? 4 : 0
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

    func tvPanelStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(TVColors.surfaceDark)
            )
    }
}

#Preview("TVFocusBorderModifier") {
    VStack(spacing: 30) {
        Text("Focused Border Panel")
            .padding(24)
            .tvPanelStyle()
            .tvFocusBorder(isFocused: true)
        Text("Unfocused Border Panel")
            .padding(24)
            .tvPanelStyle()
            .tvFocusBorder(isFocused: false)
    }
    .padding(60)
    .background(TVColors.background)
}
