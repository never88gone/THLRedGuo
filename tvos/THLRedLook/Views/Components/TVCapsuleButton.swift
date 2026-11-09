import SwiftUI

// MARK: - 统一胶囊焦点按钮（分类栏、Tab、选集分段、筛选标签）
public struct TVCapsuleButton: View {
    public let title: String
    public var isSelected: Bool = false
    public var isFocused: Bool = false
    public var isCompact: Bool = false
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
        isCompact: Bool = false,
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
        self.isCompact = isCompact
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
                isCompact: isCompact,
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

#Preview("TVCapsuleButton") {
    HStack(spacing: 16) {
        TVCapsuleButton(title: "全部短剧", isSelected: true, isFocused: true) {}
        TVCapsuleButton(title: "都市爽文", isSelected: false, isFocused: false) {}
    }
    .padding(50)
    .background(TVColors.background)
}
