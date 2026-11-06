import SwiftUI

// MARK: - 统一标准矩形焦点按钮
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
                    .foregroundColor(effectiveFocused ? .white : (isProminent ? .white : TVColors.primary))
            }
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(effectiveFocused ? .white : TVColors.textPrimary)
            }
        }
        .padding(.horizontal, title.isEmpty ? 20 : 28)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isProminent
                        ? (effectiveFocused ? AnyShapeStyle(TVColors.prominentGradient) : AnyShapeStyle(TVColors.primary))
                        : (effectiveFocused ? AnyShapeStyle(LinearGradient(colors: [TVColors.buttonFocusedGradStart, TVColors.buttonFocusedGradEnd], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(TVColors.buttonNeutral))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    effectiveFocused ? Color.white : (isProminent ? Color.clear : TVColors.borderSubtle),
                    lineWidth: effectiveFocused ? 3.0 : 1.0
                )
        )
        .scaleEffect(effectiveFocused ? 1.08 : 1.0)
        .shadow(
            color: effectiveFocused ? TVColors.focusedShadowStrong : Color.clear,
            radius: effectiveFocused ? 16 : 0,
            x: 0,
            y: effectiveFocused ? 4 : 0
        )
        .animation(TVTheme.focusSpringAnimation, value: effectiveFocused)
    }
}

#Preview("TVButton Showcase") {
    VStack(spacing: 20) {
        TVButton(title: "立即播放", icon: "play.fill", isProminent: true, isFocused: true) {}
        TVButton(title: "加入追剧", icon: "heart", isProminent: false, isFocused: false) {}
    }
    .padding(60)
    .background(TVColors.background)
}
