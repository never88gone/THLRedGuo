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

#Preview("TVButton Showcase") {
    VStack(spacing: 20) {
        TVButton(title: "立即播放", icon: "play.fill", isProminent: true, isFocused: true) {}
        TVButton(title: "加入追剧", icon: "heart", isProminent: false, isFocused: false) {}
    }
    .padding(60)
    .background(TVColors.background)
}
