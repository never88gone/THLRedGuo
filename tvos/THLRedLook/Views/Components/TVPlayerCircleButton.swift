import SwiftUI

// MARK: - 统一圆形焦点按钮（播放器核心三按键）
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
                .foregroundColor(TVColors.textPrimary)
                .padding(padding)
                .background(
                    Circle()
                        .fill(isProminent ? (effectiveFocused ? TVColors.primaryHover : TVColors.primary) : (effectiveFocused ? TVColors.surfaceFocused : Color.black.opacity(0.85)))
                )
                .tvCircleFocus(isFocused: effectiveFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

#Preview("TVPlayerCircleButton") {
    HStack(spacing: 30) {
        TVPlayerCircleButton(icon: "backward.fill", size: 30, padding: 16) {}
        TVPlayerCircleButton(icon: "play.fill", size: 40, padding: 22, isProminent: true, forceFocused: true) {}
        TVPlayerCircleButton(icon: "forward.fill", size: 30, padding: 16) {}
    }
    .padding(60)
    .background(TVColors.background)
}
