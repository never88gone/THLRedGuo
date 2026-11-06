import SwiftUI

// MARK: - 统一胶囊焦点边框修饰器
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
                    .stroke(isFocused ? TVColors.focusedBorderColor : Color.clear, lineWidth: lineWidth)
            )
            .shadow(
                color: isFocused ? TVColors.focusedShadowColor : Color.clear,
                radius: 12,
                y: 0
            )
            .scaleEffect(isFocused ? scale : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
            .focusEffectDisabled()
    }
}

public extension View {
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
}

#Preview("TVCapsuleFocusModifier") {
    Text("Capsule Tag")
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(TVColors.surfaceCard)
        .clipShape(Capsule())
        .tvCapsuleFocus(isFocused: true)
        .padding(50)
        .background(TVColors.background)
}
